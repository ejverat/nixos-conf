#!/usr/bin/env bash
#
# diag-gear5th.sh — collect the facts needed to debug a gear5th session
# problem (niri not starting / hanging, GPU, seat, xwayland) and write them
# to /tmp/gear5th-diag.txt for forwarding to the support agent or chopper.
#
# Read-only: never kills processes, never changes config. The manual niri
# trace step prints instructions instead of running anything destructive.
#
# Usage:
#   ./scripts/diag-gear5th.sh

set -uo pipefail

OUT=/tmp/gear5th-diag.txt

{
    echo "===== gear5th diagnostic $(date --iso-8601=seconds) ====="
    echo
    echo "--- system ---"
    uname -a
    . /etc/os-release 2>/dev/null && echo "PRETTY_NAME=$PRETTY_NAME"

    echo
    echo "--- user/group ---"
    whoami
    id

    echo
    echo "--- logind sessions/seats ---"
    loginctl list-sessions 2>&1
    loginctl session-status 2>&1 | head -25
    loginctl show-session "$(loginctl 2>/dev/null | awk 'NR==2 {print $1}')" -p Seat,Active,Type,Class,State 2>&1

    echo
    echo "--- session env (relevant) ---"
    env | grep -E '^(XDG|DBUS|WAYLAND|DISPLAY|XDG_RUNTIME_DIR)' || true

    echo
    echo "--- niri processes ---"
    pgrep -a niri || echo "no niri process"
    ps -o pid,stat,etime,pcpu,wchan:32,cmd -C niri 2>/dev/null || true

    echo
    echo "--- xwayland ---"
    pgrep -a xwayland || echo "no xwayland/xwayland-satellite process"
    command -v Xwayland || echo "Xwayland NOT on PATH"
    command -v xwayland-satellite || echo "xwayland-satellite NOT on PATH"

    echo
    echo "--- GPU (lspci) ---"
    lspci -k 2>/dev/null | grep -iA3 -E 'vga|3d|display' || echo "(lspci unavailable or no GPU found)"

    echo
    echo "--- /dev/dri ---"
    ls -la /dev/dri 2>&1 || echo "(no /dev/dri)"

    echo
    echo "--- kernel/drm/nvidia/amdgpu/i915 logs (dmesg tail) ---"
    sudo -n dmesg 2>/dev/null | grep -iE 'drm|nvidia|amdgpu|i915|virtio|nouveau|error|fail' | tail -40 \
        || dmesg 2>/dev/null | grep -iE 'drm|nvidia|amdgpu|i915|virtio|nouveau|error|fail' | tail -40 \
        || echo "(dmesg not readable; run 'sudo dmesg ...' manually)"

    echo
    echo "--- journalctl: niri / xwayland / session mentions ---"
    journalctl -b 2>/dev/null | grep -iE 'niri|xwayland|session' | tail -50 || echo "(journalctl unavailable)"
} >"$OUT" 2>&1

echo "[+] collected -> $OUT"
echo
cat <<'EOF'
Now the manual trace step (this isolates GPU vs DRM/seat/env). From a SECOND
tty (Ctrl+Alt+F2), log in as your user and run:

  # 1) drop the stuck tty1 session back to the login prompt:
  sudo pkill -TERM -x niri

  # 2) reproduce with verbose logging (default config is fine for the test;
  #    15s auto-timeout so it can't hang your machine):
  timeout 15 niri -L trace 2>&1 | tail -40

  # 3) GPU bisect: if trace hangs, force software rendering and retry:
  timeout 15 env LIBGL_ALWAYS_SOFTWARE=1 niri -L trace 2>&1 | tail -40

Rules of interpretation:
  - trace step 2 completes (renders)       -> GPU/DRM ok; problem is later
  - trace 2 hangs, trace 3 (swrast) works  -> hardware GL/driver path is the
    problem (nixpkgs mesa vs Debian GPU drivers)
  - both hang                              -> DRM/seat/kernel or env issue
  - last log line before the hang          -> report this line

Forward /tmp/gear5th-diag.txt plus the trace tails to the support agent
(docs/gear5th-support.md) or to chopper.
EOF