# Feature: consolidate shared-layer duplication (allowUnfree + provider-keys paths)

## Goal

Remove two small sources of duplication between chopper (NixOS) and gear5th
(standalone) that could silently diverge:

1. `config.allowUnfree = true` repeated in every manual `import nixpkgs`.
2. The provider-keys env path hardcoded in four places across two modules.

## Decisions

- **`modules/lib/_pkgs.nix`**: one function `nixpkgs: system: import nixpkgs { … }`
  with `allowUnfree`, used by the three manual imports. The leading underscore
  keeps import-tree from evaluating it as a flake-parts module.
  - `modules/parts.nix` (flake-level perSystem pkgs)
  - `modules/hosts/gear5th/default.nix` (standalone pkgs)
  - `modules/features/orcaslicer.nix` (the dedicated `nixpkgs-orca` pin)
  - **Deliberately unchanged**: chopper's `nixpkgs.config.allowUnfree = true` is
    the NixOS module-system way of setting the policy; it is not a manual import.
- **`modules/lib/_paths.nix`**: the two provider-keys paths as constants.
  - `providerKeysEnvNixos` = `/run/secrets/rendered/pi-provider-keys.env`
  - `providerKeysEnvPortable` = `.config/pi-provider-keys.env` (relative to `$HOME`)
  - Read by `modules/features/secrets.nix` (both the NixOS and home variants) and
    `modules/features/zsh.nix` (both the `myZsh` and `myZshPortable` wrappers).
  - **Why a constant and not a `nixosConf` option**: the zsh wrappers are built
    in `perSystem`, which cannot read the NixOS `config`. A `nixosConf` option
    would only reach the secrets module, leaving the wrapper literals behind.

## Tasks

1. Add `modules/lib/_pkgs.nix`; use it in `parts.nix`, `gear5th`, `orcaslicer`.
2. Add `modules/lib/_paths.nix`; use it in `secrets.nix` and `zsh.nix`.

## Verification evidence

Behavior-preserving refactor: both host drv paths must be **identical** to the
`main` baseline.

- chopper toplevel: `fg94h97599ix7g6wfngl36z7vgghjaw7-nixos-system-chopper-26.11.20260902.3ed67ec.drv`
  (identical).
- gear5th activationPackage: `8rzhqsgj6sh4zapi1gpchgv6jr1s2yb0-home-manager-generation.drv`
  (identical).
- `nix flake check --no-build` -> all checks passed.

## Commit identities

- [ ] `refactor: consolidate the manual nixpkgs import policy`
- [ ] `refactor: centralize the provider-keys env paths`
