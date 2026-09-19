# Feature: chopper migrates to the shared home-manager layer (phase 2)

## Goal

Make `chopper` (NixOS) consume the same `flake.homeModules.*` as `gear5th`, so
the user-level configuration has a single source of truth and the manual
`~/.dotfiles` clone on chopper can be retired.

## Phase 2 complete (validated on hardware)

- **chopper**: `sudo nixos-rebuild switch` applied; `home-manager-ejverat.service`
  active; `~/.dotfiles`, `~/.config/wezterm/wezterm.lua`, `~/.oh-my-zsh`,
  `~/.zsh/zsh-autosuggestions`, `~/powerlevel10k` and the oh-my-zsh plugin file
  are now `ejverat:users` symlinks managed by home-manager; `tmux`/`wezterm` come
  from `/etc/profiles/per-user/ejverat` (0 in the system profile); `ZDOTDIR` and
  `FZF_BASE` still come from the system environment; a fresh shell loads the
  highlighter (`ZSH_HIGHLIGHT_VERSION=0.8.0`) with no `source` errors.
- **gear5th**: `home-manager switch` applied cleanly (its paths were already
  user-owned); the same shared modules drive it.
- **Incidents resolved during the migration**:
  1. root-owned leftovers from the removed zsh activationScripts blocked the
     first slice-4 switch on chopper (migration note below);
  2. the shared module baked a wrong subpath for `zsh-syntax-highlighting`
     (`share/zsh/zsh-syntax-highlighting/…` instead of
     `share/zsh-syntax-highlighting/…`), a silent failure at shell start, fixed
     in `76a4e37`. `scripts/diag-gear5th.sh` now verifies every baked store path
     in `~/.oh-my-zsh-custom/plugins/*/*.plugin.zsh`.

## Decision: how home-manager runs on chopper

Use the **home-manager NixOS module** (`inputs.home-manager.nixosModules.home-manager`
via `home-manager.users.ejverat`), not standalone. Reasons:

- `nixos-rebuild switch` stays the single command; no second activation path.
- The same `flake.homeModules.*` values import directly into the user config.
- System integration (sessions, `/etc`, setuid wrappers, sops) stays declarative
  in NixOS where it belongs.

The earlier attempt in `stash@{0}` ("HomeManager attempt") took the standalone
route and hand-rolled `homeConfigurations` outside flake-parts; it is superseded
by this design rather than applied.

Settings: `useGlobalPkgs = true`, `useUserPackages = true`,
`backupFileExtension = "bak"` (so a leftover real file is moved aside instead of
aborting activation), `extraSpecialArgs = { flakeSelf; flakeInputs; }` to match
what the shared home modules expect.

## Migration map (user-level → home modules, system-level stays)

| Feature | Action | Notes |
|---|---|---|
| `dotfiles` | **move** | retires the manual `~/.dotfiles` clone on chopper |
| `wezterm`, `tmux` | **move** | pure user packages |
| `neovim` | **move** | `EDITOR` moves from `environment.variables` to the HM session var |
| `zsh` | **split** | stub: `users.users.ejverat.shell` and `programs.zsh.enable` stay NixOS; `ZDOTDIR`, plugin symlinks and secret sourcing come from HM (the system `activationScripts.zsh-plugin-symlinks` is deleted) |
| `pi`, `gentle-pi`, `engram` | **move packages, keep activation** | the `~/.pi/agent/settings.json` merge stays a system activation (pi owns that file at runtime); only the packages move to the user profile |
| `niri` | **keep NixOS** | `programs.niri` provides the session/DM integration; the shared niri home module would duplicate it (it also adds the user unit + Xwayland for the standalone case) |
| `noctalia` | **keep as-is** | on chopper `~/.config/noctalia/settings.json` is user-owned runtime state synced back with `sync-noctalia`; HM-managing it would make it a read-only store symlink and break that workflow |
| `secrets` | **keep NixOS** | root sops rendering stays system-side; the chopper zsh flavor keeps sourcing `/run/secrets/rendered/pi-provider-keys.env` |
| `pam` | **not needed** | NixOS provides the setuid `unix_chkpwd` |
| slack, claude-code, antigravity, chrome, chromium, gimp, libreoffice, hyprpicker, kanshi, teams, deepseek-harness, opencode | **later batches** | same mechanism once each is needed on both hosts |

## Slices (each verified before the next)

1. **Infra**: home-manager NixOS module + `home-manager.users.ejverat` with the
   host identity; no feature imports yet.
2. **Simple user apps**: `wezterm`, `tmux`, `dotfiles` (retire the manual clone).
3. **neovim**.
4. **zsh** (split: system shell stub + HM rc/plugins; delete the activationScripts).
5. **pi/gentle-pi/engram** (packages to the profile; activation untouched).

## Pre-switch action for the user (slice 2)

`~/.dotfiles` on chopper is a live checkout, and the old installer left
`~/.config/nvim` and `~/.config/wezterm` as **symlinks into it** (they would
dangle once the checkout moves, and home-manager needs to create
`~/.config/wezterm/wezterm.lua` itself):

```sh
git -C ~/.dotfiles status --short           # must be clean
diff -rq ~/.dotfiles/config/nvim nixos-conf/dotfiles/config/nvim | head
mv ~/.dotfiles ~/.dotfiles.bak
rm ~/.config/nvim ~/.config/wezterm         # stale symlinks; HM recreates what is needed
sudo nixos-rebuild switch --flake .#chopper
# verify
ls -l ~/.dotfiles/config/nvim ~/.config/wezterm/wezterm.lua
```

Verified before switching: the vendored copies are byte-identical to the live
checkout (nvim, tmux, wezterm, `.zshrc`) and the checkout had no uncommitted
changes, so nothing is lost.

## Status

- [x] Slice 1 — infra (home-manager NixOS module, `useGlobalPkgs`,
  `useUserPackages`, `backupFileExtension = "bak"`, `extraSpecialArgs`)
- [x] Slice 2 — wezterm/tmux moved to the user profile, `dotfiles` vendored tree
  materialized at `~/.dotfiles`
- [x] Slice 4 — zsh: the shared home module now owns the plugins and the
  `~/.oh-my-zsh`, `~/.oh-my-zsh-custom`, `~/.zsh/zsh-autosuggestions` and
  `~/powerlevel10k` symlinks on both hosts, replacing chopper's bespoke
  `system.activationScripts.zsh-plugin-symlinks`; the wrapper flavor is
  host-specific through `nixosConf.zsh.wrapper` (`myZsh` on chopper,
  `myZshPortable` on gear5th, which is also gear5th's login-shell binary).
  System-side and deliberately kept: `users.users.ejverat.shell`, `ZDOTDIR`
  (verified the wrapper does NOT set it itself) and `FZF_BASE`.
- [x] ~~Slice 3 (neovim)~~ — discarded: the shared value (the config) already
  comes from the vendored dotfiles; moving only the package gains nothing, and
  moving `EDITOR` to HM would lose it in shells because the wrapper runs with
  `hmSessionVariables = null` (it never sources `hm-session-vars.sh`).
- [x] ~~Slice 5 (pi/gentle-pi/engram)~~ — discarded: the `~/.pi/agent/settings.json`
  merge has to stay a system activation (pi rewrites that file at runtime) and
  gear5th installs those agents from npm, so relocating the packages is churn.

## Migration note: root-owned leftovers from the old zsh activation

The removed `system.activationScripts.zsh-plugin-symlinks` ran as **root**, so it
left root-owned paths in the user's home:

```
lrwxrwxrwx root root ~/.oh-my-zsh
lrwxrwxrwx root root ~/powerlevel10k
drwxr-xr-x root root ~/.zsh                    (contains the autosuggestions symlink)
drwxr-xr-x root root ~/.oh-my-zsh-custom       (contains the syntax-highlighting plugin file)
```

home-manager activates as the user, so it cannot create or replace entries inside
those directories: the first slice-4 switch failed with
`ln: failed to create symbolic link '/home/ejverat/.zsh/zsh-autosuggestions': Permission denied`
and `home-manager-ejverat.service` ended up `failed` (the system generation still
switched, so the fix is just to finish the HM part).

One-time cleanup, then re-switch:

```sh
rm -f ~/.oh-my-zsh ~/powerlevel10k                 # symlinks to the same targets
sudo rm -rf ~/.zsh ~/.oh-my-zsh-custom             # root-owned dirs, HM recreates them
sudo nixos-rebuild switch --flake .#chopper
systemctl status home-manager-ejverat.service      # expect active
```

The same class of problem applies to any future host that migrates away from a
root-run activation: check ownership with `ls -ld` before expecting HM to manage
those paths.

## Verification (slices 1, 2, 4)

- `nix flake check` — all checks passed.
- chopper: toplevel eval + full build; the built `activate` no longer contains
  `zsh-plugin-symlinks`; the user profile now ships `zsh` (myZsh) and `fzf`; the
  home-manager generation stages `.oh-my-zsh`, `.oh-my-zsh-custom/plugins/
  zsh-syntax-highlighting/*.plugin.zsh`, `.zsh/zsh-autosuggestions` and
  `powerlevel10k` with the same store targets the old activation used.
- gear5th: activation package builds and still contains `home-path/bin/zsh`
  (the login shell must stay in the profile for GC safety).
- Post-switch on chopper (slices 1-2): HM user environment identical to the
  locally verified one, `/etc/set-environment` identical, no HM `.bak` conflicts,
  `~/.dotfiles/{config/nvim,config/tmux,config/wezterm,home/.zshrc,utilities/cht.sh}`
  and `~/.config/wezterm/wezterm.lua` are HM symlinks.
