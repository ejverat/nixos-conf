# chopper — NixOS host

Disaster-recovery runbook: rebuild this machine from a fresh NixOS install.
Everything user-level is in this repo; only the state listed under *Before you
wipe* has to come from a backup.

## What this host is

- NixOS (x86_64-linux), hostname `chopper`, user `ejverat` (`sudo` + `wheel`),
  ASUS laptop with Intel CPU + hybrid NVIDIA/AMD graphics.
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
tool needs. Clipboard is not part of this: lan-mouse does not implement it. Why
every libei-based alternative is unusable on niri is in
`odd/tasks/lan-mouse-kvm.md`.

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
