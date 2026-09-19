# nixos-conf

Dendritic Nix configuration for two machines:

| Host | OS | Managed by |
| --- | --- | --- |
| `chopper` | NixOS | `nixosConfigurations.chopper` (`nixos-rebuild switch --flake .#chopper`) |
| `gear5th` | Debian | `homeConfigurations.gear5th` (home-manager standalone) |

**Reinstalling a machine?** Each host has a rebuild runbook with the exact order of
commands and what to back up first:
[docs/chopper.md](docs/chopper.md) · [docs/gear5th.md](docs/gear5th.md).
For gear5th failures there is also the AI-agent troubleshooting catalog in
[docs/gear5th-support.md](docs/gear5th-support.md).

Shared *user-level* features live in `modules/features/*.nix` as
`flake.homeModules.*`, used by both hosts. System-level features stay
NixOS-only (`flake.nixosModules.*`) until chopper migrates to the shared
layer. Portable dotfiles are vendored in `dotfiles/` and materialized at
`~/.dotfiles` by the `dotfiles` home module, so the wrapper packages
(`wrapper-modules`) reference the same paths on both machines.

## Rebuild chopper (NixOS)

```sh
sudo nixos-rebuild switch --flake .#chopper
```

chopper's user-level configuration runs through the home-manager NixOS module
(same `flake.homeModules.*` as gear5th), so one command activates both. Phase 2
tracker: `odd/tasks/chopper-home-manager.md`.

## Bootstrap gear5th (Debian)

The quick path runs the one-shot script (interactive by default):

```sh
./scripts/bootstrap-gear5th.sh            # interactive
./scripts/bootstrap-gear5th.sh --yes      # headless (needs passwordless sudo)
```

Manual steps (what the script automates), and the AI-agent troubleshooting
catalog, live in [docs/gear5th-support.md](docs/gear5th-support.md).

### 0. System layer (apt + systemd)

Firmware, Bluetooth, audio, printers and hardware modules are Debian's job, not
Nix's:

```sh
./scripts/debian-system-services.sh           # install + enable
./scripts/debian-system-services.sh --check   # read-only report
```

### 1. Install Nix

```sh
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

### 2. Clone and build

```sh
git clone git@github.com:ejverat/nixos-conf.git ~/nixos-conf
cd ~/nixos-conf
nix build .#homeConfigurations.gear5th.activationPackage
```

### 3. Make the portable zsh the login shell

The login shell must be a **stable path** — `~/.nix-profile/bin/zsh` — not the
store path of one build (that goes stale on every switch and GC can break
login). One root command is needed because `chsh` only accepts shells listed
in `/etc/shells`. From the repo on gear5th, after the first activation:

```sh
ls -l ~/.nix-profile/bin/zsh                       # present after activation
echo "$HOME/.nix-profile/bin/zsh" | sudo tee -a /etc/shells
chsh -s "$HOME/.nix-profile/bin/zsh"
```

### 4. Activate home-manager

First activation installs the `home-manager` CLI into the profile, so later
switches are:

```sh
~/.nix-profile/bin/home-manager switch --flake ~/nixos-conf#gear5th
```

or directly:

```sh
nix run ~/nixos-conf#homeConfigurations.gear5th.activationPackage
```

### 5. Start niri (session)

Pick one launch path:

**Display manager (GDM)** — recommended with a Bluetooth keyboard:

```sh
cd ~/nixos-conf && ./scripts/install-niri-session.sh   # session file + enable GDM/bluetooth
./scripts/fix-pam-unix-chkpwd.sh                       # lock screen PAM (setuid helper)
# pair the keyboard (needs it before the greeter is usable):
bluetoothctl power on && bluetoothctl scan on   # put the keyboard in pairing mode
bluetoothctl pair <MAC> && bluetoothctl trust <MAC> && bluetoothctl connect <MAC>
sudo reboot                                      # then pick "Niri" in GDM
```

The session file Execs the stable `~/.nix-profile/bin/niri-session`; that script
re-runs under your login shell (which puts the nix profile on PATH) and starts
the `niri.service` user unit that the niri home module links into
`~/.config/systemd/user/`.

**tty1 autostart** — no display manager:

Debian display managers cannot load wayland sessions from the nix store, so in
this mode niri is started from tty1 by the portable zsh wrapper (`exec niri`
when no display is running). Disable any DM first:

```sh
sudo systemctl disable --now gdm   # or sddm / lightdm / ly
```

Hit Ctrl+Alt+F1 (or reboot) and log in — niri takes over tty1.

### First things to validate on gear5th

- niri session + GPU: drivers stay with Debian; niri brings its own nixpkgs
  mesa. If something misbehaves (`wayland-info`, missing GPU accel), start
  here before touching anything else.
- Provider keys for pi: drop them in `~/.config/zsh/secrets.zsh` (sourced by
  the dotfiles .zshrc when present). sops-nix home-manager integration is a
  planned follow-up; chopper renders the same secrets from root sops to
  `/run/secrets/rendered/pi-provider-keys.env`.

## Portability notes

- `modules/features/*.nix` export the NixOS module (chopper), the home module
  (shared), or both. Home modules receive `flakeSelf`/`flakeInputs` via
  `extraSpecialArgs` (see `modules/hosts/gear5th/default.nix`).
- Keep host-specific HM modules inline in each host's `default.nix`:
  import-tree turns every `.nix` under `modules/` into a flake-parts module,
  which would mis-evaluate a plain home-manager module file.
- Adding a new portable app = add/use the `flake.homeModules.<name>` in the
  feature file and import it in the host's module list.

## Roadmap

1. **Migrate chopper to the shared layer** (phase 2): the stashed "HomeManager
   attempt" (`stash@{0}`) already sketches it, but re-do it on top of the
   existing `flake.homeModules.*` instead of applying the old draft, then retire
   the manual `~/.dotfiles` clone on chopper.
2. **sops-nix for home-manager on gear5th** (age key based) so pi's provider
   keys stop living in `~/.config/zsh/secrets.zsh`.
3. **More apps through the same mechanism**, in batches, when needed on both
   machines. Inventory taken from the archived `debian-migration` draft
   (`archive/debian-migration-draft` tag):
   - desktop: kanshi (HDMI-A-1 + eDP-1 profiles are in the archived tag),
     hyprpicker
   - files: thunar (+ archive-plugin, volman), file-roller, gvfs, tumbler
   - media: gimp, feh, nomacs, imagemagick
   - browsers/comms: firefox, chromium, google-chrome, slack
   - CLI/dev: bat, fd, direnv, tree, pciutils, upower, docker-client, ollama
4. **System layer stays with Debian**: `scripts/debian-system-services.sh`
   installs/enables it (apt + systemd), with `--check` for a read-only report.