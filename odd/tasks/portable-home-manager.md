# Feature: portable home-manager layer for Debian (gear5th)

## Goal

Make the user-level configuration portable between NixOS (`chopper`) and Debian
(`gear5th`) using Nix only, without migrating chopper's NixOS system modules
yet (Option B: shared layer, gear5th first).

Target apps (first batch): Neovim, Wezterm, niri + noctalia, pi, tmux, plus the
zsh base the session depends on. Later batches extend the same mechanism.

## Decisions

- **Home-manager standalone on gear5th** via `homeConfigurations.gear5th`,
  driven from the same dendritic flake (flake-parts + import-tree).
- **Features stay dendritic**: each portable feature file exports both
  `flake.nixosModules.<name>` (chopper, unchanged) and the new
  `flake.homeModules.<name>` (shared user layer). Home modules receive
  `flakeSelf` / `flakeInputs` via `extraSpecialArgs` so they can reference the
  flake's own `perSystem` packages (wrapper-modules wrappers are pure and
  portable as-is).
- **Dotfiles get vendored** into `dotfiles/` at repo root (outside `modules/`,
  so import-tree ignores it) and materialized by home-manager at `~/.dotfiles/*`
  on gear5th. This keeps the exact paths the wrappers already reference
  (`$HOME/.dotfiles/config/nvim`, `config/tmux/tmux.conf`, `home/.zshrc`,
  `utilities/cht.sh`) so the same wrapper packages work on both machines.
  Known Option-B tradeoff: chopper keeps its manual `~/.dotfiles` until phase 2.
- **Secrets (sops) deferred**: chopper renders provider keys to
  `/run/secrets/rendered/pi-provider-keys.env` via root sops; gear5th has no root
  sops. The user's `.zshrc` already supports `~/.config/zsh/secrets.zsh`, so
  gear5th starts without Nix-managed secrets and adds sops-nix home-manager
  later (follow-up task, needs an age key for gear5th).
- **niri session on Debian**: no display manager manages nix-store sessions, so
  gear5th starts niri from tty1 in the portable zsh wrapper (`exec niri` when
  `WAYLAND_DISPLAY` is empty and tty is tty1). Runbook disables any DM.
- **GPU on gear5th is the early risk area**: niri brings its own nixpkgs mesa
  against Debian kernel drivers; validate `niri` session + `wayland-info` first.

## Tasks

1. Add `home-manager` flake input (nixpkgs follows) and update flake.lock.
2. Vendor portable dotfiles (`config/nvim`, `config/tmux`, `config/wezterm`,
   `home/.zshrc`, `utilities/cht.sh`) into `dotfiles/`.
3. Home modules for neovim, wezterm, tmux (packages + file materialization).
4. Home module for zsh: portable wrapper (`myZshPortable`), oh-my-zsh /
   plugin / p10k symlinks, tty1 niri autostart.
5. Home modules for niri and noctalia (package + noctalia settings.json).
6. Port pi wrapper to `perSystem` (`packages.myPi`), keep chopper's nixosModule
   behavior identical, add home module.
7. `modules/hosts/gear5th`: `homeConfigurations.gear5th` + host `home.nix`.
8. Verify: build gear5th activationPackage, eval chopper toplevel (unchanged).
9. Document gear5th bootstrap runbook (README).

## Verification evidence

- `nix build .#homeConfigurations.gear5th.activationPackage` succeeds.
- `nix eval .#nixosConfigurations.chopper.config.system.build.toplevel.drvPath`
  still evaluates after the pi refactor.
- Commit identities recorded below as they land.