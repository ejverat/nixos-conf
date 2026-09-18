# Feature: chopper migrates to the shared home-manager layer (phase 2)

## Goal

Make `chopper` (NixOS) consume the same `flake.homeModules.*` as `gear5th`, so
the user-level configuration has a single source of truth and the manual
`~/.dotfiles` clone on chopper can be retired.

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
- [ ] Slice 3 — neovim
- [ ] Slice 4 — zsh
- [ ] Slice 5 — pi/gentle-pi/engram

Verified for slices 1-2: `nix flake check`, toplevel eval, full toplevel build
(`nix build .#nixosConfigurations.chopper.config.system.build.toplevel`, 16s),
and the built generation inspected: `result/etc/profiles/per-user/ejverat/bin`
has `tmux`/`wezterm` (system profile no longer ships them) and the
home-manager generation stages `~/.dotfiles/{config/nvim,config/tmux,
config/wezterm,home/.zshrc,utilities/cht.sh}` plus
`~/.config/wezterm/wezterm.lua`.
