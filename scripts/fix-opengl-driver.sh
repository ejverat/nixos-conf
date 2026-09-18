#!/usr/bin/env bash
#
# fix-opengl-driver.sh — make nixpkgs' GL work on a non-NixOS host (gear5th).
#
# nixpkgs patches its GL stack to look for drivers under /run/opengl-driver, a
# tree NixOS creates at boot. On Debian the path does not exist, so niri fails
# in two stages:
#
#   1. libgbm cannot load its backend:
#        MESA-LOADER: failed to open dri: /run/opengl-driver/lib/gbm/dri_gbm.so
#        WARN niri::backend::tty: error adding primary node device
#   2. libglvnd cannot find an EGL vendor (compiled-in search dirs):
#        /run/opengl-driver/share/glvnd/egl_vendor.d:/etc/glvnd/egl_vendor.d:/usr/share/glvnd/egl_vendor.d
#        DEBUG niri::backend::tty: ... Unable to obtain a valid EGL Display.
#
# This script resolves the mesa package from the flake's own niri closure and
# symlinks the same subdirectories NixOS exposes, then persists them with a
# systemd tmpfiles.d entry so they survive reboots. Re-run it after nixpkgs
# lock updates (store hashes change).
#
# Usage (needs root; the script re-execs itself with sudo):
#   ./scripts/fix-opengl-driver.sh

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    exec sudo --preserve-env "$0" "$@"
fi

REPO_DIR="${REPO_DIR:-$HOME/nixos-conf}"
TMPFILES=/etc/tmpfiles.d/nix-opengl-driver.conf
ROOT=/run/opengl-driver

echo "[*] resolving mesa from the niri closure in $REPO_DIR"
if [ ! -f "$REPO_DIR/flake.nix" ]; then
    echo "[x] flake not found at $REPO_DIR (set REPO_DIR)" >&2
    exit 1
fi

closure="$(mktemp)"
trap 'rm -f "$closure"' EXIT
# shellcheck disable=SC2164
(cd "$REPO_DIR" && nix path-info -r .#packages.x86_64-linux.myNiri) > "$closure"

MESA_ROOT=""
while IFS= read -r p; do
    if [ -z "$MESA_ROOT" ] && [ -f "$p/lib/gbm/dri_gbm.so" ] && [ -d "$p/share/glvnd/egl_vendor.d" ]; then
        MESA_ROOT="$p"
    fi
done < "$closure"

if [ -z "$MESA_ROOT" ]; then
    echo "[x] no mesa package with dri_gbm.so + glvnd vendor found in the niri closure." >&2
    echo "    Build it first: nix build .#packages.x86_64-linux.myNiri" >&2
    exit 1
fi

echo "[*] mesa: $MESA_ROOT"

mkdir -p "$ROOT/lib" "$ROOT/share/glvnd" "$ROOT/share/vulkan"

link() { # link <target> <linkname>
    [ -e "$1" ] || return 0
    ln -sfn "$1" "$2"
    echo "[+] $2 -> $1"
}

{
    echo "# Managed by nixos-conf/scripts/fix-opengl-driver.sh — re-run it after"
    echo "# nixpkgs lock updates because the store hashes change."
    echo "d $ROOT 0755 root root -"
    echo "d $ROOT/lib 0755 root root -"
    echo "d $ROOT/share/glvnd 0755 root root -"
    echo "d $ROOT/share/vulkan 0755 root root -"
} > "$TMPFILES"

add_tmpfiles_line() { # add_tmpfiles_line <linkname> <target>
    printf 'L+ %s - - - - %s\n' "$1" "$2" >> "$TMPFILES"
}

link "$MESA_ROOT/lib/dri" "$ROOT/lib/dri"
link "$MESA_ROOT/lib/gbm" "$ROOT/lib/gbm"
link "$MESA_ROOT/share/glvnd/egl_vendor.d" "$ROOT/share/glvnd/egl_vendor.d"
[ -d "$MESA_ROOT/lib/dri" ] && add_tmpfiles_line "$ROOT/lib/dri" "$MESA_ROOT/lib/dri"
[ -d "$MESA_ROOT/lib/gbm" ] && add_tmpfiles_line "$ROOT/lib/gbm" "$MESA_ROOT/lib/gbm"
[ -d "$MESA_ROOT/share/glvnd/egl_vendor.d" ] && add_tmpfiles_line "$ROOT/share/glvnd/egl_vendor.d" "$MESA_ROOT/share/glvnd/egl_vendor.d"

# Vulkan ICDs are not needed by niri, but the same tree serves any nix Vulkan
# app on this host.
if [ -d "$MESA_ROOT/share/vulkan/icd.d" ]; then
    link "$MESA_ROOT/share/vulkan/icd.d" "$ROOT/share/vulkan/icd.d"
    add_tmpfiles_line "$ROOT/share/vulkan/icd.d" "$MESA_ROOT/share/vulkan/icd.d"
fi

echo "[+] persisted $TMPFILES"
systemd-tmpfiles --create "$TMPFILES" >/dev/null 2>&1 || true

echo
echo "[+] $ROOT now contains:"
find "$ROOT" -maxdepth 3 -mindepth 1 | sort
echo
echo "[+] Next: sudo pkill -TERM -x niri, relogin on tty1, then"
echo "    tail -80 /run/user/\$(id -u)/niri-console.log"