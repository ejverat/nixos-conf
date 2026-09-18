#!/usr/bin/env bash
#
# install-niri-session.sh — register the niri session for a display manager on
# a non-NixOS host (gear5th) and, by default, enable GDM + bluetooth.
#
# Display managers only scan /usr/share/wayland-sessions (GDM hardcodes it), so
# nix-store session files are invisible; and the session file the niri package
# ships uses `Exec=niri-session`, which the DM's minimal PATH cannot resolve.
# This script installs a session file whose Exec is the STABLE profile path:
#
#   Exec=$HOME/.nix-profile/bin/niri-session
#
# niri-session re-execs itself under the user's login shell (which prepends the
# nix profile to PATH, see myZshPortable) and then starts the systemd user unit
# niri.service, which the niri home module links into ~/.config/systemd/user/.
#
# Usage (run as your user; it re-execs itself with sudo for the root part):
#   ./scripts/install-niri-session.sh            # install session + enable GDM
#   ./scripts/install-niri-session.sh --no-gdm   # only write the session file

set -euo pipefail

SESSION_FILE=/usr/share/wayland-sessions/niri.desktop
ENABLE_GDM=1
for arg in "$@"; do
    case "$arg" in
        --no-gdm) ENABLE_GDM=0 ;;
        *) echo "[x] unknown argument: $arg" >&2; exit 2 ;;
    esac
done

# ── Phase 1 (user): verify the profile session entry point ─────────────────
if [ "$(id -u)" -ne 0 ]; then
    NIRI_SESSION="$HOME/.nix-profile/bin/niri-session"
    if [ ! -x "$NIRI_SESSION" ]; then
        echo "[x] $NIRI_SESSION not found." >&2
        echo "    Run the home-manager activation first: home-manager switch --flake ~/nixos-conf#gear5th" >&2
        exit 1
    fi
    if [ ! -f "$HOME/.config/systemd/user/niri.service" ]; then
        echo "[x] ~/.config/systemd/user/niri.service not found (niri.service is what" >&2
        echo "    niri-session starts). Re-run the home-manager activation." >&2
        exit 1
    fi
    echo "[*] user phase: session Exec = $NIRI_SESSION"
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    exec sudo USER_HOME="$HOME" NIRI_SESSION="$NIRI_SESSION" ENABLE_GDM="$ENABLE_GDM" "$0"
fi

# ── Phase 2 (root): session file + services ────────────────────────────────
: "${NIRI_SESSION:?run this script as your user (it re-execs with sudo)}"
: "${USER_HOME:?missing USER_HOME}"

mkdir -p "$(dirname "$SESSION_FILE")"

if [ -e "$SESSION_FILE" ] && ! grep -q 'nixos-conf' "$SESSION_FILE" 2>/dev/null; then
    cp -n "$SESSION_FILE" "$SESSION_FILE.bak"
    echo "[!] existing $SESSION_FILE backed up to $SESSION_FILE.bak"
fi

cat > "$SESSION_FILE" <<EOF
[Desktop Entry]
Name=Niri
Comment=A scrollable-tiling Wayland compositor (nixos-conf)
Exec=$NIRI_SESSION
Type=Application
DesktopNames=niri
EOF
chmod 0644 "$SESSION_FILE"
echo "[+] wrote $SESSION_FILE:"
sed 's/^/    /' "$SESSION_FILE"

if [ "${ENABLE_GDM:-1}" = 1 ]; then
    if ! systemctl cat gdm.service >/dev/null 2>&1; then
        cat >&2 <<'EOF'
[x] gdm.service not found: this system has no GDM installed.
    Install it:  sudo apt install gdm3
    Or use a lighter greeter (listed sessions come from
    /usr/share/wayland-sessions, which this script fills):
      sudo apt install greetd tuigreet
EOF
    else
        # Debian starts the DM from graphical.target through the
        # display-manager.service alias. Enabling the unit alone is not enough
        # when the machine still boots to multi-user.target.
        before_default="$(systemctl get-default)"
        if [ "$before_default" != "graphical.target" ]; then
            systemctl set-default graphical.target
            echo "[+] default target: $before_default -> graphical.target"
        else
            echo "[=] default target already graphical.target"
        fi

        # Debian ships gdm.service as a STATIC unit (no [Install] section), so
        # `systemctl enable gdm` alone cannot create any boot-time wiring, and
        # the display-manager.service alias Debian normally uses is removed
        # when the DM is disabled (which the tty-mode bootstrap does). Without
        # either, nothing pulls GDM in at boot even with graphical.target as
        # the default. Restore the install metadata via a drop-in and let
        # systemd wire it exactly like the Debian package does.
        install -d /etc/systemd/system/gdm.service.d
        cat > /etc/systemd/system/gdm.service.d/10-nixos-conf-enable.conf <<'EOF'
# Managed by nixos-conf/scripts/install-niri-session.sh
# gdm.service is static on Debian (no [Install]); this restores the wiring so
# graphical.target pulls in the display manager again.
[Install]
Alias=display-manager.service
WantedBy=graphical.target
EOF
        echo "[+] wrote /etc/systemd/system/gdm.service.d/10-nixos-conf-enable.conf"

        systemctl daemon-reload
        systemctl enable gdm >/dev/null 2>&1 || true
        echo "[+] gdm.service enabled: $(systemctl is-enabled gdm 2>&1)"
        systemctl restart gdm >/dev/null 2>&1 || systemctl start gdm >/dev/null 2>&1 || true
        sleep 1

        echo "[*] current state:"
        echo "    default target : $(systemctl get-default)"
        echo "    gdm enabled    : $(systemctl is-enabled gdm 2>&1)"
        echo "    gdm active     : $(systemctl is-active gdm 2>&1)"
        if [ -L /etc/systemd/system/display-manager.service ]; then
            echo "    display-manager: -> $(readlink -f /etc/systemd/system/display-manager.service)"
        else
            echo "    display-manager: MISSING (no alias for other tools to find)"
        fi
        if [ -L /etc/systemd/system/graphical.target.wants/gdm.service ]; then
            echo "    boot-time hook : graphical.target.wants/gdm.service OK"
        else
            echo "    boot-time hook : MISSING -> GDM will NOT start at boot"
        fi
    fi

    if systemctl list-unit-files --type=service 2>/dev/null | grep -q '^bluetooth.service'; then
        systemctl enable --now bluetooth >/dev/null 2>&1 && echo "[+] bluetooth.service enabled (for the BT keyboard)"
    fi
fi

cat <<EOF

[+] Done. Next steps:
    1. Pair the Bluetooth keyboard (needed before it works at the greeter):
         bluetoothctl power on
         bluetoothctl scan on          # put the keyboard in pairing mode
         bluetoothctl pair <MAC>
         bluetoothctl trust <MAC>
         bluetoothctl connect <MAC>
    2. Reboot (or: sudo systemctl restart gdm), then pick "Niri" in GDM.

    Note: with GDM owning a tty, the tty1 autostart in myZshPortable stays
    inert; niri now starts from the session file above.
EOF