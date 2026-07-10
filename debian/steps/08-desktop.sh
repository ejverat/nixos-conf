#!/usr/bin/env bash
# 08-desktop.sh — Desktop config: niri, Noctalia, kanshi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../common.sh"

heading "08: Desktop configuration"

USER_HOME="$HOME"
USER_NAME="$(whoami)"

# ── Kanshi (display profiles) ──
setup_kanshi() {
    mkdir -p "$USER_HOME/.config/kanshi"

    if [ -f "$USER_HOME/.config/kanshi/config" ]; then
        msg "Kanshi config already exists"
    else
        cat > "$USER_HOME/.config/kanshi/config" << 'KANSHI'
# Kanshi display profiles — ported from NixOS modules/features/kanshi.nix

profile home {
    output HDMI-A-1 enable scale 1.0 mode 1920x1080@60.000Hz position 0,0
    output eDP-1 enable scale 1.0 mode 1366x768@60.003Hz position 0,1080
}

profile docked {
    output HDMI-A-1 enable scale 1.0 mode 1920x1080@60.000Hz position 0,0
}

profile laptop {
    output eDP-1 enable scale 1.0 mode 1366x768@60.003Hz position 0,0
}
KANSHI
        msg "Kanshi config written"
    fi
}

# ── Noctalia (desktop shell) ──
setup_noctalia() {
    mkdir -p "$USER_HOME/.config/noctalia"
    local noctalia_json="$REPO_DIR/modules/features/noctalia.json"

    if [ -f "$noctalia_json" ]; then
        python3 -c "
import json, os
with open('$noctalia_json') as f:
    cfg = json.load(f)
settings = cfg.get('settings', cfg)
dest = os.path.expanduser('$USER_HOME/.config/noctalia/settings.json')
with open(dest, 'w') as f:
    json.dump(settings, f, indent=2)
"
        msg "Noctalia settings extracted from flake"
    else
        warn "noctalia.json not found at $noctalia_json"
        warn "Noctalia will use default settings"
    fi
}

# ── Niri session (for display manager) ──
setup_niri_session() {
    local sessions_dir="$USER_HOME/.local/share/wayland-sessions"
    mkdir -p "$sessions_dir"

    if [ -f "$sessions_dir/niri.desktop" ]; then
        msg "Niri desktop entry already exists"
    else
        cat > "$sessions_dir/niri.desktop" << 'NIRI_DESKTOP'
[Desktop Entry]
Name=Niri
Comment=Niri Wayland compositor
Exec=env XDG_CURRENT_DESKTOP=niri niri-session
Type=Application
NIRI_DESKTOP
        msg "Niri desktop entry created (visible in display manager)"
    fi
}

# ── Kanshi systemd user service ──
setup_kanshi_service() {
    local svc_dir="$USER_HOME/.config/systemd/user"
    mkdir -p "$svc_dir"

    cat > "$svc_dir/kanshi.service" << 'KANSHI_SVC'
[Unit]
Description=Kanshi output management daemon
After=graphical-session-pre.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.nix-profile/bin/kanshi
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=default.target
KANSHI_SVC

    # Enable (but don't start — it waits for graphical session)
    XDG_RUNTIME_DIR="/run/user/$(id -u "$USER_NAME")" \
        systemctl --user enable kanshi.service 2>/dev/null || true
    msg "Kanshi systemd user service installed"
}

# ── Run ──
setup_kanshi
setup_noctalia
setup_niri_session
setup_kanshi_service

chown -R "$USER_NAME:$USER_NAME" "$USER_HOME/.config" "$USER_HOME/.local" 2>/dev/null || true

msg "Desktop configuration complete"
msg "Log in with Ly → select 'Niri' → Noctalia will start automatically"
