#!/usr/bin/env bash
# 02-nix.sh — Validate or install Nix
# Checks for existing installation before attempting install.
# Safe to re-run — will skip if Nix is already working.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

heading "02: Nix package manager"

# ── Validation checks ──
nix_binary_exists()   { command -v nix &>/dev/null; }
nix_daemon_active()   { systemctl is-active --quiet nix-daemon 2>/dev/null; }
nix_works()           { nix --version &>/dev/null; }
user_in_nix_group()   { groups "$(whoami)" 2>/dev/null | grep -qw nix-users; }

# ── Report current state ──
if nix_binary_exists; then
    msg "nix binary found: $(nix --version 2>/dev/null || echo 'unknown version')"
else
    info "nix binary not found"
fi

if nix_daemon_active; then
    msg "nix-daemon is running"
else
    info "nix-daemon is not running"
fi

if nix_works; then
    msg "nix command functional"
fi

if [ -d /nix ]; then
    msg "/nix store exists ($(du -sh /nix 2>/dev/null | cut -f1))"
fi

# ── Decision ──
if nix_binary_exists && nix_daemon_active && nix_works; then
    msg "Nix is fully operational — skipping installation"
    exit 0
fi

if nix_binary_exists && ! nix_daemon_active; then
    warn "Nix binary exists but daemon is not running"
    info "Attempting to start nix-daemon…"
    sudo systemctl start nix-daemon 2>/dev/null || true
    if nix_daemon_active; then
        msg "nix-daemon started"
        exit 0
    else
        warn "Could not start nix-daemon — will reinstall"
    fi
fi

# ── Install ──
warn "Nix not fully installed — installing now"
sudo install -d -m 0755 /nix 2>/dev/null || true

info "Downloading and running the Nix deterministic installer…"
# Using the official multi-user installer (daemon mode)
sh <(curl -L https://nixos.org/nix/install) --daemon

# Source nix immediately
if [ -f /etc/profile.d/nix.sh ]; then
    # shellcheck disable=SC1091
    . /etc/profile.d/nix.sh
fi

# ── Verify ──
if nix_binary_exists && nix_works; then
    msg "Nix installed successfully: $(nix --version 2>/dev/null)"
else
    fail "Nix installation failed. Check the output above."
fi

msg "Nix is ready"
