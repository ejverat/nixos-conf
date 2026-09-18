# nixos-conf

Dendritic Nix configuration for two machines:

| Host | OS | Managed by |
| --- | --- | --- |
| `chopper` | NixOS | `nixosConfigurations.chopper` (`nixos-rebuild switch --flake .#chopper`) |
| `gear5th` | Debian | `homeConfigurations.gear5th` (home-manager standalone) |

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

## Bootstrap gear5th (Debian)

The quick path runs the one-shot script (interactive by default):

```sh
./scripts/bootstrap-gear5th.sh            # interactive
./scripts/bootstrap-gear5th.sh --yes      # headless (needs passwordless sudo)
```

Manual steps (what the script automates), and the AI-agent troubleshooting
catalog, live in [docs/gear5th-support.md](docs/gear5th-support.md).

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

Debian display managers cannot load wayland sessions from the nix store, so
niri is started from tty1 by the portable zsh wrapper (`exec niri` when no
display is running). If a DM owns tty1, disable it first:

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

1. Migrate chopper's user-level features to the shared home modules (retire
   the manual `~/.dotfiles` clone on chopper).
2. sops-nix home-manager secrets for gear5th (age key based).
3. Remaining apps (kanshi, hyprpicker, docker-as-user…) through the same
   mechanism when they are needed on both machines.