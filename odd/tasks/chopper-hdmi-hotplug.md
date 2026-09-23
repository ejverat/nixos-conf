# Feature: make HDMI hotplug survive on chopper

## Goal

Plugging the external monitor into `chopper` while a session is running leaves
the panel black until the compositor is restarted. The connector *is* detected,
so this is not a detection problem: something refuses to scan out. Fix the cause
on the host that owns it (`modules/hosts/chopper/configuration.nix`) and record
the operational escape hatch for the cases the driver still gets wrong.

## Evidence

### Topology

```
card1-HDMI-A-1  -> PCI 0000:01:00.0  (NVIDIA TU117M GTX 1650 Mobile)
card2-eDP-1     -> PCI 0000:00:02.0  (Intel UHD 630, i915)
```

The HDMI port is wired to the dGPU, and niri picks i915 as its render node:

```
niri: using as the render node: "/dev/dri/renderD129"    (i915)
niri: adding device: 57858 "/dev/dri/card2"  this is the primary node
niri: adding device: 57857 "/dev/dri/card1"  (NVIDIA, secondary)
```

So the external output is a cross-GPU destination: niri renders on i915 and
copies to the NVIDIA plane, which needs a hardware semaphore on the destination
plane.

### The failure

Kernel log for the failing hotplug (2026-09-23 12:23:05, boot 0):

```
nv_drm_atomic_apply_modeset_config [nvidia_drm] *ERROR* Failed to initialize semaphore for plane fence
nv_drm_atomic_commit              [nvidia_drm] *ERROR* Failed to apply atomic modeset.  Error code: -11
...
nv_drm_atomic_commit              [nvidia_drm] *ERROR* Flip event timeout on head 0
```

`-11` is `EAGAIN`. The driver rejects the atomic commit while the compositor is
enabling the freshly attached output; niri then waits for a page flip that never
completes, and 27 s later the kernel declares it lost. The connector still
reports `connected`, which is exactly why the monitor looks "detected but black".

### Intermittence, and the one anomaly that is not intermittent

Every earlier hotplug in the retained journal succeeded without a single
`nv_drm` error: 2026-09-20 22:47:17, 2026-09-21 07:04:53 and 2026-09-21
13:04:53. The bug is a race, not a deterministic break.

Grepping every retained kernel log for the NVIDIA framebuffer console
registration returns exactly one hit, in the failing trace and 200 ms before the
rejected commit:

```
2026-09-23 12:23:04.793831 nvidia 0000:01:00.0: [drm] fb1: nvidia-drmdrmfb frame buffer device
```

That is `nvidia-drm`'s fbdev emulation taking the connector over as a console
framebuffer the moment the hotplug event creates it.

### Why a restart "fixes" it

It does not fix anything, it buys a retry. From the recovery on the same day:

| Time | Event |
| --- | --- |
| 12:23:04.862 | niri connects HDMI-A-1 at the 75 Hz preferred mode |
| 12:23:05.003 | kanshi reconfigures to 60 Hz -> **commit fails with EAGAIN** |
| 12:23:29 | session is quit |
| 12:23:42.953 | niri restarts -> first commit **also fails** |
| 12:23:48.159 | second commit (60 Hz) -> **succeeds** |

A hotplug that never gets a successful retry stays black for the whole boot.
This is why logging out and back in sometimes helps and sometimes does not.

## Decisions

- **Disable `nvidia-drm`'s fbdev emulation.** It is the only anomaly present in
  the failing trace and absent from the successful ones, it is reversible, and
  it is one line. NixOS has no dedicated option: the nvidia module sets
  `nvidia-drm.fbdev = 1` unconditionally whenever `modesetting.enable` is on and
  the driver is 545 or newer
  (`nixos/modules/hardware/video/nvidia.nix`, the
  `lib.optional (offloadCfg.enable || cfg.modesetting.enable) && versionAtLeast 545`
  guard). The public `hardware.nvidia.moduleParams` escape hatch is the
  supported way through, and it needs `lib.mkForce`: a plain value collides with
  the module's own definition under the `attrsOf (attrsOf raw)` type.
  `nvidia-drm` is an allowed key — the module's own assertion whitelists
  `nvidia`, `nvidia-drm`, `nvidia-modeset` and `nvidia-uvm`.
- **The console is not lost.** `fbcon` is bound to `i915drmfb` (`fb0`) because
  i915 owns the boot VGA device; the NVIDIA framebuffer was a second, unused
  console.
- **Do not touch `powerManagement`.** It is correctly off. Enabling runtime PM
  would make this class of wake-up race worse, not better.
- **Rank the remaining candidates but do not apply them yet**, because each is
  more invasive and only one should be live at a time:
  1. `hardware.nvidia.open = false` — the failure is in the open module's
     plane-fence semaphore path, and TU117 is supported by both modules.
  2. Pin a driver branch other than 595.99.02.
- **Keep the operational escape hatch documented**, because the fix is a
  hypothesis until the monitor is actually plugged in and comes up:
  `niri msg output HDMI-A-1 off && niri msg output HDMI-A-1 on` retries the
  commit without a session restart.
- **`-11` is a retryable code.** A future niri that retried `EAGAIN` itself
  would mask this; not our call to make here, and no upstream report was filed
  because no network research tools are available in this session.

## Tasks

1. Override `hardware.nvidia.moduleParams.nvidia-drm.fbdev` to `0` in the
   chopper host module, with the evidence in a comment.
2. Verify the generated module option and the rendered
   `/etc/modprobe.d/nixos.conf` line, and that both hosts still evaluate.
3. Document the workaround and correct the graphics topology line in
   `docs/chopper.md`.

## Verification evidence

Config-level verification is complete; the behavioural claim is not, and cannot
be from inside this session.

- `hardware.nvidia.moduleParams` before the change:
  `{"nvidia-drm":{"fbdev":1,"modeset":1}}`, which is what the running
  `/etc/modprobe.d/nixos.conf` line 10 renders as
  `options nvidia-drm fbdev=1 modeset=1`.
- The `mkForce` mechanism was verified independently by replaying the nixpkgs
  merge pattern through `lib.evalModules`: the `mkMerge`-defined default plus a
  plain `0` raises `conflicting definition values`, and the same `0` under
  `lib.mkForce` yields `{"nvidia-drm":{"fbdev":0,"modeset":1}}` with `modeset`
  untouched.
- After the change, `nix eval --json
  .#nixosConfigurations.chopper.config.hardware.nvidia.moduleParams` returns
  `{"nvidia-drm":{"fbdev":0,"modeset":1}}`.
- `nix build .#nixosConfigurations.chopper.config.system.build.toplevel`
  succeeds and renders the intent:

  ```
  $ diff -r /run/current-system/etc/modprobe.d \
      /nix/store/0ks2w7lspvby14qrmrdqzjwg0qcyrl7f-nixos-system-chopper-26.11.20260902.3ed67ec/etc/modprobe.d
  10c10
  < options nvidia-drm fbdev=1 modeset=1
  ---
  > options nvidia-drm fbdev=0 modeset=1
  ```

  That single line is the **only** difference in the whole `etc/modprobe.d`
  tree, which is the evidence that the change is surgical rather than a rebuild
  side effect.
- `nix flake check --no-build` -> `all checks passed!`, so gear5th's
  home configuration still evaluates against the shared modules.
- **Confirmed by the user (2026-09-23)** after deploying the change: the monitor
  comes up on hotplug without restarting the session, which is the behaviour that
  was missing. Because the failure was intermittent, this is one clean
  confirmation rather than a statistical claim; `journalctl -k -b 0 | grep nv_drm`
  remains the check if it ever recurs, and the two fallbacks above stay ranked for
  that case.

## Delivery

- Issue #61 (`fix(chopper): the HDMI monitor detects but stays black after a
  hotplug`, labels `type:bug` + `status:approved`).
- Branch `fix/chopper-hdmi-hotplug` off `main` at `a4efce2`.
- Commits `ba5d7cf` (host module + this record) and `f4818d4` (runbook), plus the
  `docs(chopper)` close-out commit that adds this section.
- PR #62 against `main`, label `type:bug`, body links `Closes #61`.
- The repository has no CI workflows, so no checks run; merge remains the user's
  decision.
