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
    echo
    echo "--- /run/opengl-driver (nixpkgs GL path; must exist on non-NixOS) ---"
    ls -l /run/opengl-driver/lib 2>&1 || echo "(missing — nixpkgs libgbm cannot load its GBM backend)"
    echo
    echo "--- live niri IPC (if a niri is running) ---"
    # niri >= 26.04 names the IPC socket niri.<wayland-display>.<pid>.sock
    # (not niri.sock); discover it instead of guessing.
    niri_sock="$(ls /run/user/1000/niri.*.sock 2>/dev/null | head -1)"
    if [ -n "$niri_sock" ]; then
        ok_msg="(NIRI_SOCKET=$niri_sock)"
        export NIRI_SOCKET="$niri_sock"
    else
        ok_msg="(no niri IPC socket found in /run/user/1000)"
    fi
    echo "$ok_msg"
    niri msg version 2>&1 || echo "(no niri instance answering IPC)"
    niri msg -j outputs 2>&1 || true
    niri msg workspaces 2>&1 || true
} >"$OUT" 2>&1

echo "[+] collected -> $OUT"
echo
cat <<'EOF'
Now the live checks first (non-intrusive). niri 26.04 removed the -L/--log-level
flag and renamed the IPC socket to niri.<wayland-display>.<pid>.sock (the old
niri.sock no longer exists), so discover it and use NIRI_SOCKET explicitly:

  SOCK=$(ls /run/user/1000/niri.*.sock 2>/dev/null | head -1)
  echo "$SOCK"                                    # exists == niri is fully up
  NIRI_SOCKET=$SOCK niri msg version
  NIRI_SOCKET=$SOCK niri msg outputs              # empty list == the bug
  NIRI_SOCKET=$SOCK niri msg workspaces

Cross-check from the protocol side (same user, any session):

  env WAYLAND_DISPLAY=wayland-1 nix shell nixpkgs#wayland-utils -c wayland-info \
    | grep -A3 wl_output

Interpretation:
  - msg outputs lists a connector / wayland-info shows a wl_output
    -> niri is rendering to an output; the problem is the screen/session.
  - msg outputs is EMPTY / no wl_output globals
    -> niri runs outputless: DRM/modeset or connector issue (with amdgpu,
    check the dmesg DRM lines and /dev/dri from the collected file above).

Manual reproduction with default logs (only if the instance was killed), on a
second tty (Ctrl+Alt+F2); it prints richer output than the default start and
can't hang your machine thanks to timeout:

  sudo pkill -TERM -x niri
  timeout 15 niri 2>&1 | tail -60                                  # default logs
  timeout 15 env LIBGL_ALWAYS_SOFTWARE=1 niri 2>&1 | tail -60      # swrast bisect

Rules of interpretation:
  - manual run renders                -> GPU/DRM ok; problem is later
  - manual run hangs, swrast works    -> hardware GL/driver path is the problem
  - both hang                         -> DRM/seat/kernel or env issue
  - last log line before the hang     -> report this line

Forward /tmp/gear5th-diag.txt plus the tails to the support agent
(docs/gear5th-support.md) or to chopper.
EOF