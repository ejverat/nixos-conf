#!/usr/bin/env bash
#
# fix-pam-unix-chkpwd.sh — make PAM password checks work for user processes on
# a non-NixOS host (gear5th), so the noctalia/quickshell lock screen accepts the
# password.
#
# nixpkgs' pam_unix.so has the setuid helper path compiled in as
# /run/wrappers/bin/unix_chkpwd — that is the path NixOS's security.wrappers
# creates. On Debian it does not exist, so a non-root PAM conversation cannot
# read /etc/shadow and every authentication fails:
#
#   niri lock (noctalia -> Quickshell.Services.Pam) -> "wrong password"
#
# This script installs a persistent setuid-root copy of nixpkgs' unix_chkpwd,
# links it at the compiled-in path (via tmpfiles.d, because /run is tmpfs) and
# writes a minimal PAM service for the locker. Re-run it after nixpkgs lock
# updates (the store hash changes).
#
# Usage (run as your user; it re-execs itself with sudo for the root part):
#   ./scripts/fix-pam-unix-chkpwd.sh

set -euo pipefail

REPO_DIR="${REPO_DIR:-$HOME/nixos-conf}"
HELPER_DEST=/usr/local/libexec/nix-unix_chkpwd
WRAPPER_PATH=/run/wrappers/bin/unix_chkpwd
PAM_SERVICE=noctalia-lock
PAM_SERVICE_FILE="/etc/pam.d/$PAM_SERVICE"
TMPFILES=/etc/tmpfiles.d/nix-pam-unix-chkpwd.conf

# ── Phase 1 (user): resolve the matching pam helper ────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    if [ ! -f "$REPO_DIR/flake.nix" ]; then
        echo "[x] flake not found at $REPO_DIR (set REPO_DIR)" >&2
        exit 1
    fi

    nix_bin="$(command -v nix || true)"
    if [ -z "$nix_bin" ]; then
        for c in "$HOME/.nix-profile/bin/nix" /nix/var/nix/profiles/default/bin/nix; do
            if [ -x "$c" ]; then
                nix_bin="$c"
                break
            fi
        done
    fi
    [ -n "$nix_bin" ] || { echo "[x] nix not found in PATH" >&2; exit 1; }

    pam_path="$(cd "$REPO_DIR" && "$nix_bin" eval --raw .#packages.x86_64-linux.linuxPam.outPath)"
    if [ ! -x "$pam_path/bin/unix_chkpwd" ]; then
        echo "[x] $pam_path/bin/unix_chkpwd not found" >&2
        exit 1
    fi
    echo "[*] phase 1/2 (user): pam helper from $pam_path"
    exec sudo PAM_PATH="$pam_path" REPO_DIR="$REPO_DIR" "$0"
fi

# ── Phase 2 (root): setuid helper + PAM service ────────────────────────────
: "${PAM_PATH:?run this script as your user (it re-execs with sudo)}"

mkdir -p /usr/local/libexec
install -o root -g root -m 4755 "$PAM_PATH/bin/unix_chkpwd" "$HELPER_DEST"
echo "[+] installed setuid helper: $HELPER_DEST"
ls -l "$HELPER_DEST"

mkdir -p /run/wrappers/bin
if [ -e "$WRAPPER_PATH" ] && [ ! -L "$WRAPPER_PATH" ]; then
    echo "[!] $WRAPPER_PATH exists and is not a symlink (NixOS-managed?); leaving a backup"
    mv "$WRAPPER_PATH" "$WRAPPER_PATH.bak"
fi
ln -sfn "$HELPER_DEST" "$WRAPPER_PATH"
echo "[+] linked $WRAPPER_PATH -> $HELPER_DEST"
ls -l "$WRAPPER_PATH"

cat > "$TMPFILES" <<EOF
# Managed by nixos-conf/scripts/fix-pam-unix-chkpwd.sh
d /run/wrappers 0755 root root -
d /run/wrappers/bin 0755 root root -
L+ $WRAPPER_PATH - - - - $HELPER_DEST
EOF
systemd-tmpfiles --create "$TMPFILES" >/dev/null 2>&1 || true
echo "[+] persisted $TMPFILES"

# Minimal service for the locker: only pam_unix, so it does not depend on the
# distribution's full stack (Debian's login/common-* also reference modules
# nixpkgs' pam does not ship, e.g. pam_cap and pam_systemd).
if [ ! -e "$PAM_SERVICE_FILE" ]; then
    cat > "$PAM_SERVICE_FILE" <<'EOF'
# Minimal PAM service for the noctalia/quickshell lock screen.
# Uses nixpkgs' pam_unix, whose setuid helper is
# /run/wrappers/bin/unix_chkpwd (installed by
# nixos-conf/scripts/fix-pam-unix-chkpwd.sh).
auth      required   pam_unix.so
account   required   pam_unix.so
EOF
    echo "[+] wrote $PAM_SERVICE_FILE"
else
    echo "[=] $PAM_SERVICE_FILE already exists; leaving it untouched"
fi

cat <<EOF

[+] Done. The lock screen authenticates through PAM now.

    Verification:
      ls -l $HELPER_DEST          # must be -rwsr-xr-x root root (setuid)
      ls -l $WRAPPER_PATH         # symlink to the helper
      ls -l $PAM_SERVICE_FILE     # minimal service

    Then lock the session again (Super+Alt+L) and unlock with your password.
    If it still fails, the locker's log is in the niri user unit journal:
      journalctl --user -u niri -e | grep -i -E 'pam|auth'

    The locker uses $PAM_SERVICE when NOCTALIA_PAM_SERVICE is exported by the
    session (set in the noctalia home module) and falls back to 'login'
    otherwise; both work with the helper installed.
EOF