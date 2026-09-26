# Feature: make the HDMI output on chopper survive suspend and hotplug

## Goal

On `chopper`, the external monitor is wired to the NVIDIA dGPU while niri renders
on the Intel iGPU. When the dGPU loses its display state — after a resume, or when
the output is re-attached — `nvidia-drm` rejects the compositor's atomic commit
and the panel stays black for the rest of the boot. Get the output back without a
reboot, and record what actually causes it.

This supersedes `odd/tasks/chopper-hdmi-hotplug.md`, whose root cause (fbdev
emulation) is falsified below.

## Evidence

### The first fix did not hold

`hardware.nvidia.moduleParams.nvidia-drm.fbdev = lib.mkForce 0` (`8937ad7`, PR #62)
is active and the identical failure recurred:

```
$ grep nvidia-drm /etc/modprobe.d/nixos.conf
options nvidia-drm fbdev=0 modeset=1

$ for f in /sys/class/graphics/fb*/name; do echo "$f: $(cat $f)"; done
/sys/class/graphics/fb0/name: i915drmfb
```

There is no `fb1: nvidia-drmdrmfb` device and no such line in the failing traces,
so the "one anomaly present in the failing trace" reasoning no longer holds. The
2026-09-23 confirmation was a single successful hotplug on an intermittent bug.

### The trigger is the dGPU losing its state, not the cable

Current boot (`2026-09-26`, boot 0), 11 `nv_drm` errors, the relevant one:

| Time | Event |
| --- | --- |
| 18:07:01 | `PM: suspend entry (deep)` |
| 23:57:52.861 | `PM: suspend exit` |
| 23:57:53.347 | `niri: laptop lid opened` |
| 23:57:53.358 | `NVRM: Xid (PCI:0000:01:00): 13, pid=1874, name=niri, Graphics Exception: Shader Program Header 11/18 Error` |
| 23:57:53.539 | `nv_drm_atomic_apply_modeset_config *ERROR* Failed to initialize semaphore for plane fence` |
| 23:57:53.539 | `nv_drm_atomic_commit *ERROR* Failed to apply atomic modeset. Error code: -11` (`EAGAIN`) |
| 00:00:40 | `nv_drm_atomic_commit *ERROR* Flip event timeout on head 0` |

niri's side of the same commit:

```
WARN niri::backend::tty: error queueing frame: The underlying drm surface
encountered an error: DRM access error: Page flip commit failed on device
`Some("/dev/dri/card2")` (Invalid argument (os error 22))
```

`card2` is the NVIDIA node (`card1` is i915, `eDP-1`). niri never retries an
`EAGAIN` commit, so `niri msg outputs` keeps listing `HDMI-A-1` at
`1920x1080@60.000` while nothing is scanned out.

`Xid 13` (`Shader Program Header Error`) is the GPU executing a command stream
whose shader memory is gone: the application context survived the resume, the
VRAM it points at did not. It appears in 3 of the 5 boots in the retained journal
that show the failure (boots 0, -1, -4). Boots -2 and -5 failed only on a real
reconnect (`niri: connecting connector: HDMI-A-1`, 2026-09-23 12:23:04 and
2026-09-20 22:47:17) without an Xid.

### Replugging does not help, a restart only buys a retry

Boot -1, after the failure at 17:35:41, every cable reconnect reproduced it:

```
17:36:08  disconnecting
17:36:12  connecting -> nv_drm_atomic_apply_modeset_config *ERROR*
17:36:29  disconnecting
17:36:34  connecting -> nv_drm_atomic_apply_modeset_config *ERROR*
17:36:50  disconnecting
17:36:56  connecting -> nv_drm_atomic_apply_modeset_config *ERROR*
17:39:00  reboot (reboot -1 ends)
```

### Driver state: what is preserved, and by whom

```
$ grep -i "DynamicPowerManagement\|PreserveVideoMemory" /proc/driver/nvidia/params
PreserveVideoMemoryAllocations: 2
DynamicPowerManagement: 3
DynamicPowerManagementVideoMemoryThreshold: 200
```

Neither value comes from this repository: the host sets
`powerManagement.enable = false; powerManagement.finegrained = false;`, and
nixpkgs only writes those module params when they are `true`
(`nixos/modules/hardware/video/nvidia.nix`). They are the defaults of the open
595.99.02 module. No `nvidia-suspend`/`nvidia-resume`/`nvidia-hibernate` units
exist on the system (`/etc/systemd/system` has none, only `nvidia-sleep.sh` inside
the driver package, unused).

So the driver is asked to preserve VRAM across suspend and nothing performs the
freeze/thaw that makes preservation work — on the userspace side *or* on the
kernel side. `NVreg_UseKernelSuspendNotifiers`, the mechanism 595 introduced to
replace those units, is unset.

The dGPU is also under ASUS `services.supergfxd` (mode `Hybrid`), which sets
runtime PM `auto` on `0000:01:00.0` with `d3cold_allowed=1`, and `/dev/dri/card2`
was re-created with the same minor at `00:03:25` — exactly at one of the failures
— while `/sys/class/drm/card2` still dates from boot.

## Decisions

- **Enable the documented suspend path for this driver version:**
  `hardware.nvidia.powerManagement.enable = true`. On this nixpkgs revision with
  `open = true` and driver 595.99.02 it has exactly three effects:
  1. `nvidia.NVreg_PreserveVideoMemoryAllocations = 1`;
  2. `nvidia.NVreg_UseKernelSuspendNotifiers = 1`, because
     `powerManagement.kernelSuspendNotifier` defaults to
     `open && versionAtLeast 595` — the driver is notified by the kernel instead
     of by systemd units;
  3. no `nvidia-suspend`/`hibernate`/`resume` units are installed (they are gated
     on `!kernelSuspendNotifier`), so no `nvidia-sleep.sh` involvement.
  This is the configuration NVIDIA documents for a hybrid laptop whose external
  output hangs off the dGPU, and it is the only change that addresses the
  post-resume context loss directly.
- **`powerManagement.finegrained` stays `false`.** Runtime D3 is a separate
  mechanism (`NVreg_DynamicPowerManagement`), already live at the driver's own
  default of 3 through `supergfxd`'s `auto` policy. Changing it belongs to the
  next test, not this one.
- **`fbdev=0` stays, unchanged, for now.** It is harmless (the console is on
  `i915drmfb`/`fb0`) and it is not the cause; reverting it in the same commit
  would put two variables in one test. Revisit it once the new configuration is
  confirmed.
- **One variable per deploy.** The remaining ranked fallbacks are
  `hardware.nvidia.moduleParams.nvidia.NVreg_DynamicPowerManagement = 0` (stop the
  dGPU from runtime-suspending at all, at a battery cost) and then
  `hardware.nvidia.open = false` or another driver branch.
- **Do not trust a single clean hotplug.** The bug is intermittent; a
  confirmation needs a suspend/resume cycle *and* a hotplug, and the check is
  `journalctl -k -b 0 | grep -E "nv_drm|Xid"`.

## Tasks

1. Set `powerManagement.enable = true` in the chopper host module and replace the
   comment that documents the falsified fbdev mechanism.
2. Verify the rendered `modprobe.d` line and the absence of user-space sleep units
   in the built system, and that both hosts still evaluate.
3. Correct `docs/chopper.md` and mark `odd/tasks/chopper-hdmi-hotplug.md`
   superseded.

## Verification evidence

Config-level verification is complete. The behavioural claim is not, and cannot
be from inside this session: it needs a reboot (the module parameters are load
time) followed by a real suspend/resume cycle and a hotplug.

- `nix eval --json .#nixosConfigurations.chopper.config.hardware.nvidia.moduleParams`
  after the change:

  ```json
  {"nvidia":{"NVreg_PreserveVideoMemoryAllocations":1,"NVreg_UseKernelSuspendNotifiers":1},"nvidia-drm":{"fbdev":0,"modeset":1}}
  ```

  The two `nvidia` entries are the whole intent; `nvidia-drm` is unchanged.
- `nix build .#nixosConfigurations.chopper.config.system.build.toplevel` succeeds,
  and the change is surgical — it is the **only** difference in the entire
  rendered `/etc` tree:

  ```
  $ diff -rq /run/current-system/etc \
      /nix/store/2z7jq27nrglg9gvj6pzqyz070cgb8brv-nixos-system-chopper-26.11.20260902.3ed67ec/etc
  Files .../etc/modprobe.d/nixos.conf and .../etc/modprobe.d/nixos.conf differ

  $ diff -r /run/current-system/etc/modprobe.d <new>/etc/modprobe.d
  9a10
  > options nvidia NVreg_PreserveVideoMemoryAllocations=1 NVreg_UseKernelSuspendNotifiers=1
  ```
- No user-space sleep units are installed, as expected with
  `kernelSuspendNotifier = true`:

  ```
  $ ls /etc/systemd/system | grep -ci nvidia            # current system
  0
  $ ls <new>/etc/systemd/system | grep -ci nvidia       # built system
  0
  $ diff -rq /run/current-system/etc/systemd/system <new>/etc/systemd/system   # no output
  ```
- `nix flake check --no-build` -> `all checks passed!`, so gear5th's home
  configuration still evaluates against the shared modules.

### On hardware (2026-09-26, first boot after `nixos-rebuild switch`)

- The parameter is live: `/proc/driver/nvidia/params` reports
  `PreserveVideoMemoryAllocations: 1` (it was `2` before), with
  `DynamicPowerManagement: 3` unchanged, as intended.
- That boot has **zero** `nv_drm`/`Xid` kernel lines, across:

  | Time | Event | Result |
  | --- | --- | --- |
  | 00:33:31 | `PM: suspend entry (deep)` | |
  | 00:33:50 | `PM: suspend exit` | panel came back without a restart |
  | 00:34:12 / 00:34:20 | disconnect / reconnect the cable | panel came back |
  | 00:34:26 / 00:35:27 | second disconnect / reconnect | panel came back |

- The user ran the deploy and the tests; this record only reports what the
  journal confirms.
- **This is encouraging, not proof.** The previous hypothesis was falsified by
  exactly this kind of single-cycle confirmation. The failures this record was
  written for include a 6-hour suspend and hotplugs that were clean for hours
  before turning bad, while the cycle tested here lasted 19 s. Treat the fix as
  unconfirmed until a few days of real suspend/resume and hotplug use, and keep
  `journalctl -k -b 0 | grep -E "nv_drm|Xid"` as the check. If it recurs, the
  next variable is `hardware.nvidia.moduleParams.nvidia.NVreg_DynamicPowerManagement = 0`,
  and only then `open = false` or another driver branch.

### Deliberately left alone

`moduleParams.nvidia-drm.fbdev = lib.mkForce 0` is still in the host module even
though its rationale is falsified; it is a no-op for this failure (proved by the
recurrence with the override active) and reverting it while testing the suspend
path would put a second variable in the same window. It is a cleanup for a
separate commit once the new configuration holds.

## Delivery

_(pending)_
