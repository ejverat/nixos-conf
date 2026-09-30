# chopper — NixOS host

Disaster-recovery runbook: rebuild this machine from a fresh NixOS install.
Everything user-level is in this repo; only the state listed under *Before you
wipe* has to come from a backup.

## What this host is

- NixOS (x86_64-linux), hostname `chopper`, user `ejverat` (`sudo` + `wheel`),
  ASUS laptop with Intel + NVIDIA hybrid graphics: an Intel UHD 630 (i915) that
  owns the internal panel and is the render node, and a GTX 1650 Mobile that
  owns the HDMI port. The two are not interchangeable; see *External monitor*
  below.
- Flake entry point: `nixosConfigurations.chopper` (`modules/hosts/chopper/`),
  activated with `nixos-rebuild switch`.
- User environment: home-manager as a **NixOS module**, importing the same
  `flake.homeModules.*` that gear5th uses — one implementation for both hosts
  (`docs/gear5th.md`).
- Secrets: sops-nix with the **SSH host key** as the age identity, rendered to
  `/run/secrets/rendered/pi-provider-keys.env`, which the zsh wrapper sources.

## Before you wipe (back these up)

| What | Path | Why |
|------|------|-----|
| SSH **host** key | `/etc/ssh/ssh_host_ed25519_key` (+ `.pub`) | it *is* the sops age identity; restoring it keeps the secrets decryptable |
| User SSH keys | `~/.ssh/` | GitHub push/pull |
| pi runtime | `~/.pi/` | not in the repo: agent settings, `mcp.json`, `npm/`, sessions, gentle-ai model-routing profiles |
| Noctalia runtime settings | `~/.config/noctalia/settings.json` | user-owned runtime state; the repo keeps a synced snapshot in `modules/features/noctalia.json` |
| This repo | `~/nixos-conf` | everything else lives here (pushed to GitHub) |

## Fresh install

### 1. Install NixOS

Keeping the same disk layout and username is the easy path:
`modules/hosts/chopper/hardware-configuration.nix` pins the filesystems by UUID
(`/` ext4 `dc80e510-…`, `/boot` vfat `398D-4321`, swap `1e54fd04-…`) and the
config bakes `ejverat` into 11 places across 7 modules.

If either changed:

```sh
sudo nixos-generate-config --show-hardware-config \
  > ~/nixos-conf/modules/hosts/chopper/hardware-configuration.nix
grep -rn ejverat modules/ | grep -v '\.md'      # every hit must be updated
```

### 2. Clone and switch

```sh
git clone https://github.com/ejverat/nixos-conf.git ~/nixos-conf
cd ~/nixos-conf
sudo nixos-rebuild switch --flake .#chopper
```

That single switch installs the system (bootloader, latest kernel, NVIDIA +
amdgpu, asusd/supergfxd, ly display manager), the home-manager user environment,
and the sops secrets.

### 3. Secrets after a reinstall

- **Restored the host key** (recommended): nothing else to do.
- **New host key**: its age recipient changed. Derive the new recipient on the
  fresh machine, add it to `.sops.yaml`, and re-encrypt from a host that can still
  decrypt (gear5th):

```sh
# on the new chopper
nix run nixpkgs#ssh-to-age -- -i /etc/ssh/ssh_host_ed25519_key.pub   # → age1…

# add that age1… to the keys list and the creation_rules in .sops.yaml, then:
cd ~/nixos-conf && git add .sops.yaml secrets/secrets.yaml
# (the re-encryption itself has to run where the old recipient is still available)
```

```sh
# on gear5th, which still holds a valid identity
cd ~/nixos-conf && git pull
sops-updatekeys secrets/secrets.yaml        # the wrapper ships with the secrets module
git commit -am "chore(secrets): add the new chopper recipient" && git push
```

### 4. Restore the runtime state

```sh
cp -a <backup>/.pi ~/
cp -a <backup>/noctalia-settings.json ~/.config/noctalia/settings.json
```

### 5. Verify

```sh
systemctl status home-manager-ejverat.service --no-pager | head -3   # active
ls -l ~/.dotfiles/config/nvim ~/.config/wezterm/wezterm.lua          # HM symlinks
echo "$ZDOTDIR"                                                      # wrapper dot dir
pi auth check --provider deepseek --json                             # {"status":"ready"}
gentle-profile current                                               # model routing
```

### 6. Shared mouse and keyboard (lan-mouse)

One physical mouse and keyboard drive this host and gear5th over the LAN.
`flake.nixosModules.lan-mouse` installs the package and opens **UDP 4242**; the
daemon runs as the user unit `lan-mouse.service`, bound to
`graphical-session.target` because it injects input through the compositor:

```sh
systemctl --user status lan-mouse.service --no-pager
```

The pairing is declarative — `nixosConf.lan-mouse.config` seeds
`~/.config/lan-mouse/config.toml`, after which lan-mouse owns the file — but the
**first authorization is a human step**: open `lan-mouse`, compare the peer's
fingerprint (`aa:bb:cc:…`, shown in gear5th's General section) and click
**Authorize** on the receiving side. The fingerprint is persisted into that same
file, which is why it is never managed by Nix.

Two checks worth running once:

```sh
getent hosts gear5th.local                        # needs avahi + mDNS (enabled here)
systemctl --user show-environment | grep WAYLAND_DISPLAY
```

If the cursor does not cross back, `Mod+Escape` releases niri's
keyboard-shortcut inhibitor (`modules/features/niri.nix`), the escape hatch a KVM
tool needs. **`Mod` is the Super key** here (niri:
`config.input.mod_key.unwrap_or(ModKey::Super)` on a TTY session; this config does
not override it). While you drive gear5th from this keyboard, **gear5th's own niri
shortcuts do not fire**: niri ignores keys injected through the virtual keyboard
(niri#403), so `Mod+…` falls through to the window there. Application shortcuts
are unaffected; for compositor actions on gear5th, use gear5th's own keyboard.
That behaviour is confirmed by hand, not merely expected. Clipboard is not part of
this: lan-mouse does not implement it. Why every libei-based alternative is
unusable on niri is in `odd/tasks/lan-mouse-kvm.md`.

## External monitor (HDMI)

The HDMI port is wired to the **NVIDIA** GPU, not to the Intel iGPU that owns
`eDP-1`, and niri renders on i915 and copies the frame across. That cross-GPU
destination is the fragile part of this host, so it is worth knowing where the
pieces are:

```sh
cat /sys/class/drm/card1-HDMI-A-1/status      # -> connected / disconnected
niri msg outputs                               # what the compositor sees
niri msg version                               # cross-check in bug reports
grep -E "nvidia" /etc/modprobe.d/nixos.conf    # -> nvidia-drm fbdev=0 modeset=1, nvidia NVreg_*
grep -i Preserve /proc/driver/nvidia/params     # -> effective suspend behaviour
```

The module options come from `modprobe.d`, not from the kernel command line:
the driver is not in `/proc/cmdline`.

**Known issue: the panel goes black when the dGPU loses its state.** The commit
fails after a resume or when the output is re-attached, not because of the
connector:

```
PM: suspend exit
niri: laptop lid opened
NVRM: Xid (PCI:0000:01:00): 13, Graphics Exception: Shader Program Header 11 Error
Failed to initialize semaphore for plane fence
Failed to apply atomic modeset.  Error code: -11   (EAGAIN)
Flip event timeout on head 0
```

`Xid 13` means the GPU ran a command stream whose shader memory is gone: the
client context survived the resume, the VRAM it points at did not. `nvidia-drm`
then rejects niri's atomic commit to the cross-GPU plane, niri never retries an
`EAGAIN` commit, and the panel stays black for the rest of the boot while
`niri msg outputs` still lists the output as configured. The connector reading
`connected` is exactly why it looks like a detection problem.

The host module therefore enables the suspend path NVIDIA documents for this
driver (`hardware.nvidia.powerManagement.enable = true`): with `open = true` and
driver 595 or newer that sets `NVreg_PreserveVideoMemoryAllocations=1` and
`NVreg_UseKernelSuspendNotifiers=1`, so the kernel freezes and thaws the driver
instead of the `nvidia-sleep.sh` systemd units, which are not installed in this
combination. Full reasoning, the falsified fbdev hypothesis and the ranked
fallbacks are in `odd/tasks/chopper-hdmi-dgpu-power.md`.

Re-attaching the cable does **not** clear it — every reconnect reproduces the
same rejection. Retry the commit without restarting the session:

```sh
niri msg output HDMI-A-1 off && niri msg output HDMI-A-1 on
```

Logging out and back in works more often, but only because it buys another
attempt, and it is not reliable. Check the kernel log to confirm which failure
this is:

```sh
journalctl -k -b 0 | grep -E "nv_drm|Xid"
```

Anything matching `nv_drm_atomic` means the driver refused again. Because the
failure is intermittent, one clean hotplug is weak evidence: confirm with a real
suspend/resume cycle **and** a hotplug before believing it is fixed.

## What is deliberately not in Nix

Nothing user-facing: NixOS owns the system, home-manager owns the user layer.
Outside Nix are only the backup items above and the encrypted secrets file, which
lives in this repo.

## If the rebuild breaks

```sh
sudo nixos-rebuild --rollback switch     # previous generation
nix flake check                          # validates the whole repo
nix eval --raw .#nixosConfigurations.chopper.config.system.build.toplevel.drvPath
git log --oneline -5                     # last known-good squashes on main
```

## Related

- `docs/gear5th.md` — the Debian host, which shares every `flake.homeModules.*`.
- `README.md` — repo layout, PR conventions, roadmap.
- `odd/tasks/chopper-home-manager.md` — why chopper consumes the shared layer and
  which parts stay system-side.
- `odd/tasks/chopper-hdmi-dgpu-power.md` — why the HDMI output goes black after a
  resume or a hotplug, the falsified fbdev hypothesis and the ranked fallbacks.
- `odd/tasks/chopper-hdmi-hotplug.md` — the earlier, superseded attempt, kept for
  the record of how the fbdev hypothesis was formed and disproved.
