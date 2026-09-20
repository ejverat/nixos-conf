# Feature: GitHub CLI on both hosts

## Goal

Have `gh` installed declaratively with Nix on both machines (chopper and
gear5th), instead of relying on an ad-hoc install.

## Decisions

- **One shared home module**, `flake.homeModules.gh` (`modules/features/gh.nix`),
  imported by both hosts. Both consume `flake.homeModules.*` already (chopper
  through the home-manager NixOS module, gear5th standalone), so a single
  module covers both without a `nixosModules` twin.
- **User-level, not system-level**: `home.packages = [ pkgs.gh ]`. The auth
  state (`~/.config/gh/hosts.yml`) is user data, like `~/.pi`; Nix installs the
  binary, the user logs in once per machine.
- `git` is already present on both hosts (chopper system packages, gear5th host
  module), so no extra dependency.

## Tasks

1. Add `modules/features/gh.nix` with `flake.homeModules.gh`.
2. Import it in `modules/hosts/gear5th/default.nix` and in chopper's
   `home-manager.users.<user>.imports`.

## Verification evidence

- `gh` present in both hosts' `home.packages`:
  `builtins.filter (p: p.pname == "gh")` → `gh-2.98.0` for
  `.#nixosConfigurations.chopper.config.home-manager.users.ejverat.home.packages`
  and `.#homeConfigurations.gear5th.config.home.packages`.
- Built profiles:
  - gear5th `home-manager-path/bin/gh` → `gh-2.98.0`, `gh version 2.98.0 (nixpkgs)`.
  - chopper `home-manager-path/bin/gh` → `gh-2.98.0`, `gh version 2.98.0 (nixpkgs)`.
- `nix build .#homeConfigurations.gear5th.activationPackage` and
  `.#nixosConfigurations.chopper.config.system.build.toplevel` → exit 0.

## Commit identities

- [ ] `feat(gh): install the GitHub CLI on both hosts`
