#!/usr/bin/env bash
# 04-bundle.sh — Install the app bundle via nix profile
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../common.sh"

require_nix

heading "04: Install app bundle"

# ── Ensure nix is in PATH ──
# shellcheck disable=SC1091
[ -f /etc/profile.d/nix.sh ] && . /etc/profile.d/nix.sh

info "Changing to repo root: $REPO_DIR"
cd "$REPO_DIR"

# ── Check if bundle is already installed ──
if nix profile list 2>/dev/null | grep -q 'debian-bundle'; then
    msg "debian-bundle is already in nix profile"
    info "To upgrade: nix profile upgrade '.*debian-bundle'"
    exit 0
fi

# ── Build / install ──
info "Building and installing debian-bundle from flake…"
info "This will download all applications — may take a while on first run."
nix profile install ".#debian-bundle"

msg "Bundle installed successfully"
msg "Binaries are available in ~/.nix-profile/bin/"
