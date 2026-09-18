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
# This script resolves the flake's own drivers output
# (.#packages.x86_64-linux.mesaDrivers, also a dependency of the niri home
# module, so the store path is GC-rooted) and then, as root, symlinks the same
# subdirectories NixOS exposes and persists them in a systemd tmpfiles.d entry
# so they survive reboots. Re-run it after nixpkgs lock updates (store hashes
# change).
#
# Usage (run as your user; it re-execs itself with sudo for the root part):
#   ./scripts/fix-opengl-driver.sh

set -euo pipefail

REPO_DIR="${REPO_DIR:-$HOME/nixos-conf}"
TMPFILES=/etc/tmpfiles.d/nix-opengl-driver.conf
ROOT=/run/opengl-driver

# ── Phase 1 (user): resolve the mesa drivers package ───────────────────────
resolve_mesa() {
    if [ ! -f "$REPO_DIR/flake.nix" ]; then
        echo "[x] flake not found at $REPO_DIR (set REPO_DIR)" >&2
        exit 1
    fi

    local nix_bin
    nix_bin="$(command -v nix || true)"
    if [ -z "$nix_bin" ]; then
        local c
        for c in "$HOME/.nix-profile/bin/nix" /nix/var/nix/profiles/default/bin/nix; do
            if [ -x "$c" ]; then
                nix_bin="$c"
                break
            fi
        done
    fi
    if [ -z "$nix_bin" ]; then
        echo "[x] nix not found in PATH (activate nix / home-manager first)" >&2
        exit 1
    fi

    # Primary: the flake's own drivers output (same pin that built libgbm and
    # libglvnd for this host, and a real dependency of the niri home module so
    # the store path is GC-rooted by the profile).
    local mesa
    mesa="$(cd "$REPO_DIR" && "$nix_bin" eval --raw .#packages.x86_64-linux.mesaDrivers.outPath 2>/dev/null || true)"

    if [ -z "$mesa" ] || [ ! -d "$mesa/lib/dri" ]; then
        echo "[x] could not resolve .#packages.x86_64-linux.mesaDrivers" >&2
        echo "    run: cd $REPO_DIR && home-manager switch --flake .#gear5th" >&2
        exit 1
    fi

    if [ ! -f "$mesa/lib/dri/radeonsi_dri.so" ] || [ ! -f "$mesa/lib/gbm/dri_gbm.so" ] \
        || [ ! -d "$mesa/share/glvnd/egl_vendor.d" ]; then
        echo "[x] $mesa is missing drivers (radeonsi_dri.so / dri_gbm.so / egl_vendor.d)" >&2
        exit 1
    fi

    printf '%s\n' "$mesa"
}

if [ "$(id -u)" -ne 0 ]; then
    echo "[*] phase 1/2 (user): resolving mesa from the niri closure in $REPO_DIR"
    MESA_ROOT="$(resolve_mesa)"
    echo "[*] mesa: $MESA_ROOT"
    echo "[*] phase 2/2 (root): creating $ROOT symlinks via sudo"
    exec sudo REPO_DIR="$REPO_DIR" MESA_ROOT="$MESA_ROOT" "$0" "$@"
fi

# ── Phase 2 (root): symlinks + tmpfiles persistence ────────────────────────
if [ -z "${MESA_ROOT:-}" ]; then
    echo "[x] run this script as your user; it re-execs itself with sudo:" >&2
    echo "    ./scripts/fix-opengl-driver.sh" >&2
    exit 1
fi

echo "[*] root phase: mesa = $MESA_ROOT"

# Never touch a system-managed tree (NixOS owns /run/opengl-driver as a symlink).
if [ -L "$ROOT" ]; then
    echo "[x] $ROOT is already a symlink (NixOS-managed). This script is for" >&2
    echo "    non-NixOS hosts; aborting without changes." >&2
    exit 1
fi

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
add_tmpfiles_line "$ROOT/lib/dri" "$MESA_ROOT/lib/dri"
add_tmpfiles_line "$ROOT/lib/gbm" "$MESA_ROOT/lib/gbm"
add_tmpfiles_line "$ROOT/share/glvnd/egl_vendor.d" "$MESA_ROOT/share/glvnd/egl_vendor.d"

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