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

- `nix build .#homeConfigurations.gear5th.activationPackage` succeeds (4s on
  chopper, store mostly warm from existing perSystem packages).
- `home-files` staged correctly: ~/.dotfiles/{config/nvim,config/tmux,
  config/wezterm,home/.zshrc,utilities/cht.sh}, ~/.config/noctalia/settings.json
  (raw settings object), ~/.config/wezterm/wezterm.lua, ~/.oh-my-zsh,
  ~/.oh-my-zsh-custom/…zsh-syntax-highlighting.plugin.zsh, ~/.zsh/zsh-autosuggestions,
  ~/powerlevel10k. Profile bins: niri, niri-session, noctalia-shell, nvim, wezterm,
  tmux, pi, fzf, git, rg, home-manager.
- `nix eval .#nixosConfigurations.chopper.config.system.build.toplevel.drvPath`
  unchanged after the pi refactor
  (q2scwwfy2lnnwjfyld0w80a3dq273lhq-nixos-system-chopper-26.11.20260902.3ed67ec.drv);
  packages.myPi = pi-coding-agent-0.85.1 (gentle-pi floor).
- `nix flake check` all checks passed.

## Lessons (for future hosts)

- Nix flakes only see git-tracked files: new files under modules/ are invisible
  until `git add` (cost ~10 min of debugging).
- import-tree imports every .nix under modules/ as a flake-parts module: host
  home-manager modules must stay inline in the host default.nix.
- home-manager flake-module (`inputs.home-manager.flakeModules.default` in
  modules/parts.nix) makes flake.homeModules mergeable; otherwise flake-parts
  rejects multi-file definitions.

## Commit identities

- 4ff91a3 feat(flake): add home-manager input for portable user config
- 9de6408 chore(dotfiles): vendor portable configs into the flake repo
- 62f83a4 feat(home): portable home modules for dotfiles, neovim, wezterm, tmux
- 9287098 feat(home): portable home modules for zsh, niri, noctalia
- 2a9af13 feat(home): pi portable package and home module
- 19624a0 feat(gear5th): home-manager host configuration for Debian
- (README runbook lands with the docs commit)

## Parallel draft: extract-then-close

A second, independent attempt was pushed from gear5th on branch
`debian-migration` (commit `e07654f`, "First draft debian migration"): an
imperative design (`debian-bundle` buildEnv + `nix profile install`, dotfiles
via stow, hand-written kanshi config, `ly` as DM). It does not contain this
branch's work and would re-hit every non-NixOS integration bug already solved
here (GBM/EGL, PAM lock, Xwayland, mesa GC root), while keeping the manual
dotfiles sync the consolidation was meant to remove.

Decision: **extract-then-close**.

- Extracted: the apt/systemd services checklist →
  `scripts/debian-system-services.sh` (with `--check`), the app inventory →
  README roadmap, and the `debian/`-era system concerns now documented in
  `docs/gear5th-support.md`.
- Corrected while extracting: no display manager install (GDM/niri come from
  `scripts/install-niri-session.sh`), pipewire/wireplumber only as packages
  (they are per-user units), no writes to shell rc files.
- Closed: the draft lives on as tag `archive/debian-migration-draft`; the
  `debian-migration` branch is deleted so there is a single implementation.
- Kanshi profiles (HDMI-A-1 1920x1080 + eDP-1 1366x768) remain available in
  that tag for the future kanshi home module.