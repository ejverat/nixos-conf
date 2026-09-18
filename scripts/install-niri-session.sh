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
    if systemctl list-unit-files gdm.service >/dev/null 2>&1; then
        systemctl enable --now gdm
        echo "[+] enabled and started gdm.service"
    else
        echo "[!] gdm.service not found; install it (sudo apt install gdm3) or enable"
        echo "    your own display manager. The session file is already in place."
    fi

    if systemctl list-unit-files bluetooth.service >/dev/null 2>&1; then
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