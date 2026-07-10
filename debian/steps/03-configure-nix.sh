#!/usr/bin/env bash
# 03-configure-nix.sh — Enable flakes, configure nix.conf
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

require_nix

heading "03: Configure Nix"

NIX_CONF="/etc/nix/nix.conf"
NEED_RESTART=false

# ── experimental-features ──
if [ -f "$NIX_CONF" ] && grep -q 'experimental-features.*flakes' "$NIX_CONF" 2>/dev/null; then
    msg "Flakes already enabled in $NIX_CONF"
else
    info "Enabling flakes + nix-command…"
    echo "experimental-features = nix-command flakes" | sudo tee -a "$NIX_CONF" > /dev/null
    NEED_RESTART=true
fi

# ── trusted-users (so normal user can use flakes without --impure) ──
if [ -f "$NIX_CONF" ] && grep -q 'trusted-users' "$NIX_CONF" 2>/dev/null; then
    msg "trusted-users already configured"
else
    info "Adding current user as trusted user…"
    echo "trusted-users = root $(whoami)" | sudo tee -a "$NIX_CONF" > /dev/null
    NEED_RESTART=true
fi

# ── Restart daemon if config changed ──
if [ "$NEED_RESTART" = true ]; then
    info "Restarting nix-daemon to apply configuration…"
    sudo systemctl restart nix-daemon
    msg "nix-daemon restarted with new config"
fi

msg "Nix configured: flakes enabled, user trusted"
