#!/usr/bin/env bash
#
# fix-opengl-driver.sh — make nixpkgs' GL work on a non-NixOS host (gear5th).
#
# nixpkgs libgbm/EGL are built to look for their drivers under
# /run/opengl-driver (a symlink NixOS creates at boot). On Debian that path
# does not exist, so niri (and every other nix GL app) fails to load the GBM
# backend and runs with zero outputs:
#
#   MESA-LOADER: failed to open dri: /run/opengl-driver/lib/gbm/dri_gbm.so
#   WARN niri::backend::tty: error adding primary node device
#
# This script resolves the mesa paths from the flake's own niri closure,
# symlinks them at /run/opengl-driver, and persists a systemd tmpfiles.d
# entry so the symlinks survive reboots. Re-run it after nixpkgs lock
# updates (store hashes change).
#
# Usage (needs root; the script re-execs itself with sudo):
#   ./scripts/fix-opengl-driver.sh
#
# Requires the niri package to be built (nix build .#packages.x86_64-linux.myNiri).

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    exec sudo --preserve-env "$0" "$@"
fi

REPO_DIR="${REPO_DIR:-$HOME/nixos-conf}"
TMPFILES=/etc/tmpfiles.d/nix-opengl-driver.conf

echo "[*] resolving mesa paths from the niri closure in $REPO_DIR"
if [ ! -f "$REPO_DIR/flake.nix" ]; then
    echo "[x] flake not found at $REPO_DIR (set REPO_DIR)" >&2
    exit 1
fi

closure="$(mktemp)"
trap 'rm -f "$closure"' EXIT
# shellcheck disable=SC2164
(cd "$REPO_DIR" && nix path-info -r .#packages.x86_64-linux.myNiri) > "$closure"

GBM_DIR=""
DRI_DIR=""
while IFS= read -r p; do
    [ -z "$GBM_DIR" ] && [ -f "$p/lib/gbm/dri_gbm.so" ] && GBM_DIR="$p/lib/gbm"
    [ -z "$DRI_DIR" ] && [ -f "$p/lib/dri/radeonsi_dri.so" ] && DRI_DIR="$p/lib/dri"
done < "$closure"

[ -n "$GBM_DIR" ] || { echo "[x] dri_gbm.so not found in the niri closure (build it first)" >&2; exit 1; }
[ -n "$DRI_DIR" ] || { echo "[x] radeonsi_dri.so not found in the niri closure (build it first)" >&2; exit 1; }

echo "[*] gbm backend:  $GBM_DIR"
echo "[*] dri drivers:  $DRI_DIR"

mkdir -p /run/opengl-driver/lib
ln -sfn "$GBM_DIR" /run/opengl-driver/lib/gbm
ln -sfn "$DRI_DIR" /run/opengl-driver/lib/dri
echo "[+] symlinks in /run/opengl-driver/lib:"
ls -l /run/opengl-driver/lib/

cat > "$TMPFILES" <<EOF
# Managed by nixos-conf/scripts/fix-opengl-driver.sh — re-run it after
# nixpkgs lock updates because the store hashes change.
d /run/opengl-driver 0755 root root -
d /run/opengl-driver/lib 0755 root root -
L+ /run/opengl-driver/lib/gbm - - - - $GBM_DIR
L+ /run/opengl-driver/lib/dri - - - - $DRI_DIR
EOF
echo "[+] persisted $TMPFILES"

systemd-tmpfiles --create "$TMPFILES" >/dev/null 2>&1 || true
echo "[+] done. Relogin on tty1 (sudo pkill -TERM -x niri first if needed) and check:"
echo "    tail -80 /run/user/\$(id -u)/niri-console.log"