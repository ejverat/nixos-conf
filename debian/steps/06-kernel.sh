#!/usr/bin/env bash
# 06-kernel.sh — Kernel modules from NixOS hardware config
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

heading "06: Kernel modules"

MODULES_FILE="/etc/modules-load.d/ejverat.conf"

# From the NixOS hardware-configuration.nix:
#   kvm-intel  (Intel CPU virtualization)
#   amdgpu     (AMD Polaris RX 580)
MODULES=(
    kvm-intel
    amdgpu
)

if [ -f "$MODULES_FILE" ]; then
    msg "Kernel modules file exists"
    info "Contents:"
    while IFS= read -r line; do
        info "  $line"
    done < "$MODULES_FILE"
else
    info "Creating $MODULES_FILE…"
    printf '%s\n' "${MODULES[@]}" | sudo tee "$MODULES_FILE" > /dev/null
    msg "Kernel modules configured: ${MODULES[*]}"
fi

msg "Kernel modules ready"
