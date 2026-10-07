#!/usr/bin/env bash
#
# debian-system-services.sh — the Debian *system* layer for gear5th.
#
# The nix/home-manager layer owns user configuration (see
# docs/gear5th-support.md). This script owns the things Nix cannot own on a
# non-NixOS host: apt packages that need systemd/dbus/udev integration, the
# Bluetooth configuration the NixOS host had, AMD firmware, and verification
# that the GPU and KVM modules are loaded.
#
# Extracted from the closed `debian-migration` draft (see the
# archive/debian-migration-draft tag) with corrections so it does not fight the
# GDM + niri session:
#   - no display manager is installed here (GDM/niri come from
#     scripts/install-niri-session.sh; greetd+tuigreet is the light alternative)
#   - pipewire/wireplumber are per-user units, so only their packages are
#     installed, never enabled as system services
#   - nothing is written to shell rc files (the login shell comes from the
#     portable zsh wrapper)
#
# Usage (run as your user; it re-execs itself with sudo for the apt/systemd part):
#   ./scripts/debian-system-services.sh                 # install + enable services
#   ./scripts/debian-system-services.sh --check         # read-only report
#   ./scripts/debian-system-services.sh --load-modules  # also persist module load
set -euo pipefail

CHECK_ONLY=0
LOAD_MODULES=0
for arg in "$@"; do
    case "$arg" in
        --check) CHECK_ONLY=1 ;;
        --load-modules) LOAD_MODULES=1 ;;
        -h|--help) awk 'NR>1 && /^set -euo/{exit} NR>1 {sub(/^# ?/, ""); print}' "$0"; exit 0 ;;
        *) echo "[x] unknown argument: $arg" >&2; exit 2 ;;
    esac
done

# System packages: services that need systemd/dbus/udev integration, hardware
# firmware, and the small tools the session configs expect (xclip for tmux
# copy, build-essential for lazy.nvim plugin builds).
APT_PACKAGES=(
    # GPU firmware (RX 580 / Polaris) + hardware
    firmware-amd-graphics
    pciutils
    upower
    # Core dumps: full cores on disk plus `coredumpctl` attribution, so the
    # next silent session crash leaves evidence instead of nothing.
    systemd-coredump
    # desktop services
    network-manager
    openssh-server
    cups
    bluez
    blueman
    avahi-daemon
    pavucontrol
    # audio/video stack (packages only; units are per-user)
    pipewire
    pipewire-pulse
    wireplumber
    # file/desktop integration
    gvfs
    gvfs-backends
    tumbler
    # session tools
    xclip
    build-essential
    git
    curl
    xz-utils
)

# Units that are genuinely system-wide.
SYSTEM_SERVICES=(
    NetworkManager
    ssh
    cups
    bluetooth
    avahi-daemon
    upower
)

BT_CONF=/etc/bluetooth/main.conf
MODULES_CONF=/etc/modules-load.d/nixos-conf.conf
COREDUMP_CONF=/etc/systemd/coredump.conf.d/nixos-conf.conf

ok() { printf '[+] %s\n' "$*"; }
msg() { printf '[*] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*"; }
err() { printf '[x] %s\n' "$*" >&2; }

# ── Checks (also used by --check) ──────────────────────────────────────────
report() {
    msg "Debian system layer status"

    if grep -qr 'non-free-firmware' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
        ok "apt: non-free-firmware component enabled"
    else
        warn "apt: non-free-firmware NOT enabled (needed for amdgpu firmware):"
        warn "     add it to /etc/apt/sources.list (e.g. ... trixie main contrib non-free-firmware)"
    fi

    if ls /lib/firmware/amdgpu/polaris10_*.bin >/dev/null 2>&1; then
        ok "firmware: amdgpu Polaris blobs present"
    else
        warn "firmware: amdgpu Polaris blobs missing (apt install firmware-amd-graphics)"
    fi

    local mod
    for mod in amdgpu kvm_intel; do
        if lsmod | grep -q "^$mod"; then
            ok "module: $mod loaded"
        else
            warn "module: $mod not loaded"
        fi
    done

    # `systemctl ... | grep -q` under `set -o pipefail` is racy: grep exits at
    # the first match, systemctl takes SIGPIPE, and the pipeline reports
    # failure, so an installed unit intermittently reads as missing. Capture
    # once and grep the captured text instead.
    local svc unit_files
    unit_files=$(systemctl list-unit-files --type=service --no-legend 2>/dev/null || true)
    for svc in "${SYSTEM_SERVICES[@]}"; do
        if grep -q "^$svc" <<<"$unit_files"; then
            printf '    %-16s enabled=%-8s active=%s\n' \
                "$svc" "$(systemctl is-enabled "$svc" 2>&1)" "$(systemctl is-active "$svc" 2>&1)"
        else
            printf '    %-16s not installed\n' "$svc"
        fi
    done

    printf '    %-16s (per-user units, expected)\n' "pipewire"
    printf '    %-16s enabled=%-8s active=%s\n' "pipewire(user)" \
        "$(systemctl --user is-enabled pipewire 2>&1)" "$(systemctl --user is-active pipewire 2>&1)"

    if [ -r /proc/sys/kernel/core_pattern ] && grep -q 'systemd-coredump' /proc/sys/kernel/core_pattern; then
        ok "coredump: core_pattern pipes to systemd-coredump"
    else
        warn "coredump: core_pattern is '$(cat /proc/sys/kernel/core_pattern 2>/dev/null)' (no systemd-coredump)"
    fi

    if [ -f "$BT_CONF" ] && grep -q 'nixos-conf/scripts/debian-system-services.sh' "$BT_CONF"; then
        ok "bluetooth: managed config present (Experimental/FastConnectable/AutoEnable)"
    else
        warn "bluetooth: managed config not present (run without --check)"
    fi
}

if [ "$CHECK_ONLY" -eq 1 ]; then
    report
    exit 0
fi

# ── Root phase ─────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    msg "user phase: checks"
    report
    msg "re-executing with sudo for the apt/systemd part"
    exec sudo LOAD_MODULES="$LOAD_MODULES" "$0"
fi

: "${LOAD_MODULES:?run this script as your user (it re-execs with sudo)}"

msg "apt update + install ${#APT_PACKAGES[@]} system packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
if ! apt-get install -y "${APT_PACKAGES[@]}"; then
    warn "apt install reported errors (some packages may be unavailable); continuing"
fi

msg "enabling system services"
unit_files=$(systemctl list-unit-files --type=service --no-legend 2>/dev/null || true)
for svc in "${SYSTEM_SERVICES[@]}"; do
    if grep -q "^$svc" <<<"$unit_files"; then
        if systemctl enable --now "$svc" >/dev/null 2>&1; then
            ok "$svc enabled"
        else
            warn "could not enable $svc"
        fi
    else
        warn "$svc unit not found; skipped"
    fi
done

# systemd-coredump: the noctalia shell died without leaving any evidence on
# 2026-10-06. Enable core collection and pin external storage so `coredumpctl`
# can attribute the next one. The package's own sysctl sets core_pattern; it is
# normally applied at boot, so re-run systemd-sysctl after installing it.
mkdir -p /etc/systemd/coredump.conf.d
if ! grep -q 'Managed by nixos-conf/scripts/debian-system-services.sh' "$COREDUMP_CONF" 2>/dev/null; then
    cat > "$COREDUMP_CONF" <<'EOF'
# Managed by nixos-conf/scripts/debian-system-services.sh
# Keep full cores on disk so `coredumpctl` can attribute the next silent
# session crash (see docs/gear5th-support.md, "the session lost all UI").
[Coredump]
Storage=external
Compress=yes
EOF
    ok "wrote $COREDUMP_CONF (Storage=external)"
else
    ok "$COREDUMP_CONF already managed"
fi
if [ -n "$(systemctl list-unit-files --no-legend 'systemd-coredump.socket' 2>/dev/null || true)" ]; then
    if systemctl enable --now systemd-coredump.socket >/dev/null 2>&1; then
        ok "systemd-coredump.socket enabled"
    else
        warn "could not enable systemd-coredump.socket"
    fi
else
    warn "systemd-coredump.socket not found; skipped"
fi
systemctl restart systemd-sysctl.service >/dev/null 2>&1 || true
ok "core_pattern: $(cat /proc/sys/kernel/core_pattern 2>/dev/null)"

# Bluetooth settings ported from the NixOS host config.
if [ -f "$BT_CONF" ] && ! grep -q 'nixos-conf/scripts/debian-system-services.sh' "$BT_CONF"; then
    cp -n "$BT_CONF" "$BT_CONF.bak"
    warn "existing $BT_CONF backed up to $BT_CONF.bak"
fi
if ! grep -q 'nixos-conf/scripts/debian-system-services.sh' "$BT_CONF" 2>/dev/null; then
    cat > "$BT_CONF" <<'EOF'
# Managed by nixos-conf/scripts/debian-system-services.sh
[General]
Experimental = true
FastConnectable = true

[Policy]
AutoEnable = true
EOF
    systemctl restart bluetooth >/dev/null 2>&1 || true
    ok "bluetooth config written (Experimental/FastConnectable/AutoEnable)"
else
    ok "bluetooth config already managed"
fi

if [ "$LOAD_MODULES" -eq 1 ]; then
    printf '%s\n' amdgpu kvm_intel > "$MODULES_CONF"
    ok "wrote $MODULES_CONF (amdgpu, kvm_intel)"
else
    msg "skipped $MODULES_CONF (pass --load-modules to persist module loading)"
fi

cat <<'EOF'

[+] System layer done. What stays manual by design:
    docker   : sudo apt install -y docker.io docker-compose-v2 uidmap
               sudo usermod -aG docker "$(whoami)"      # then relogin
    ollama   : curl -fsSL https://ollama.com/install.sh | sh
    firewall : only if you use one, e.g. sudo ufw allow proto udp to any port 5353 comment 'Avahi mDNS'
    display manager, GPU regressions, PAM lock: see docs/gear5th-support.md
EOF