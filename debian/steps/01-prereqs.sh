#!/usr/bin/env bash
# 01-prereqs.sh — System prerequisites
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

heading "01: System prerequisites"

info "Updating apt cache…"
sudo apt update

info "Installing core packages…"
sudo apt install -y curl git xz-utils

# non-free-firmware check (needed for amdgpu firmware on Polaris RX 580)
if ! grep -qr 'non-free-firmware' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
    warn "non-free-firmware not found in apt sources."
    warn "Add 'non-free-firmware' to /etc/apt/sources.list for AMD GPU firmware:"
    warn "  sudo apt edit-sources"
else
    msg "non-free-firmware enabled"
fi

msg "Prerequisites ready"
