#!/usr/bin/env bash
# 05-services.sh — System services via apt + systemd
# Handles services that need system-level integration (dbus, udev, etc.)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

heading "05: System services"

# ── Packages that need systemd integration ──
SERVICE_PACKAGES=(
    pipewire
    pipewire-pulse
    wireplumber
    network-manager
    openssh-server
    cups
    bluez
    blueman
    avahi-daemon
    upower
    pavucontrol
    gvfs
    gvfs-backends
    tumbler
)

SERVICES_SYSTEM=(
    NetworkManager
    ssh
    cups
    bluetooth
    avahi-daemon
    upower
    pipewire
    wireplumber
)

# ── Install ──
info "Installing service packages…"
sudo apt install -y "${SERVICE_PACKAGES[@]}" 2>/dev/null || warn "Some packages may not be available"

# Ly display manager
if apt-cache show ly &>/dev/null 2>&1; then
    info "Installing Ly display manager…"
    sudo apt install -y ly
    sudo systemctl enable ly.service 2>/dev/null || true
    msg "Ly display manager installed"
else
    info "Ly not in Debian repos. Building from source…"
    sudo apt install -y libpam0g-dev libxcb-xkb-dev 2>/dev/null || true
    if [ ! -d /tmp/ly ]; then
        git clone --depth 1 https://github.com/fairyglade/ly /tmp/ly
    fi
    cd /tmp/ly
    make
    sudo make install
    sudo systemctl enable ly.service 2>/dev/null || true
    msg "Ly built from source"
fi

# ── Enable systemd services ──
info "Enabling system services…"
for svc in "${SERVICES_SYSTEM[@]}"; do
    if systemctl list-unit-files --type=service 2>/dev/null | grep -q "^$svc"; then
        sudo systemctl enable --now "$svc" 2>/dev/null && msg "$svc enabled" || warn "Could not enable $svc"
    else
        info "$svc unit not found — skipping"
    fi
done

# ── Bluetooth config (from NixOS) ──
info "Configuring Bluetooth…"
sudo tee /etc/bluetooth/main.conf > /dev/null << 'BLUECONF'
[General]
Experimental = true
FastConnectable = true

[Policy]
AutoEnable = true
BLUECONF
sudo systemctl restart bluetooth 2>/dev/null || true
msg "Bluetooth configured (Experimental + FastConnectable + AutoEnable)"

# ── Firewall: mDNS (UDP 5353, from NixOS) ──
info "Opening firewall for mDNS…"
sudo ufw allow proto udp to any port 5353 comment 'Avahi mDNS' 2>/dev/null || warn "ufw not available — install with: sudo apt install ufw"
msg "Firewall rule added for mDNS"

# ── Docker ──
info "Docker daemon:"
info "  sudo apt install -y docker.io docker-compose-v2 uidmap"
info "  sudo usermod -aG docker $(whoami)"
info "  dockerd-rootless-setuptool.sh install"

# ── Ollama ──
info "Ollama daemon:"
info "  curl -fsSL https://ollama.com/install.sh | sh"

msg "System services ready"
