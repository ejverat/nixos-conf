# Feature: shared-layer hardening (chopper ↔ gear5th)

## Goal

Close the low-risk, high-return gaps found while reviewing how the
configuration is handled between chopper (NixOS) and gear5th (Debian +
home-manager standalone):

1. **Documentation drift** that contradicts the code and would send a rebuild
   down steps that no longer apply.
2. **Primary user identity hardcoded** across feature modules instead of
   declared once.
3. **No explicit eval guarantee** for both hosts in `nix flake check`.

The three are independent, small and mechanically verifiable; this is the batch
to land before the larger refactors (activation deduplication, provider-keys
path option, `allowUnfree` consolidation), which stay out of scope.

## Non-goals

- No refactor of the NixOS/home-module activation duplication in `gentle-pi`,
  `engram` or `secrets`. Own feature.
- No change to the provider-keys paths (`/run/secrets/rendered/...` on chopper,
  `~/.config/pi-provider-keys.env` on gear5th).
- No consolidation of the `allowUnfree` policy.
- **No behavior change.** Only documentation, option plumbing and checks. The
  drv paths of both hosts must be unchanged after slices 1 and 3, and the
  chopper toplevel drv path after slice 2 (a pure rename of literals).

## Baseline (verified before the first write)

- `nix eval --raw .#nixosConfigurations.chopper.config.system.build.toplevel.drvPath`
  → `/nix/store/fg94h97599ix7g6wfngl36z7vgghjaw7-nixos-system-chopper-26.11.20260902.3ed67ec.drv`
- `nix eval --raw .#homeConfigurations.gear5th.activationPackage.drvPath`
  → `/nix/store/8rzhqsgj6sh4zapi1gpchgv6jr1s2yb0-home-manager-generation.drv`
- `nix flake check --no-build --keep-going` → `all checks passed!` (no `checks`
  output exists today; `flake check` reports `homeConfigurations` only
  shallowly, without evaluating the derivation).

## Slices

### Slice 1 — Documentation drift (lowest risk, no eval impact)

Files:

- `README.md`
  - Intro: "System-level features stay NixOS-only (`flake.nixosModules.*`) until
    chopper migrates to the shared layer" — the migration happened; reword to
    state that both hosts consume `flake.homeModules.*` and system features
    stay NixOS-only.
  - Roadmap item 1 ("Migrate chopper to the shared layer (phase 2)") — done;
    `modules/hosts/chopper/configuration.nix:47-66` already imports the shared
    home modules and `odd/tasks/chopper-home-manager.md` records phase 2
    complete. Remove or mark done.
  - Roadmap item 2 ("sops-nix for home-manager on gear5th … keys stop living in
    `~/.config/zsh/secrets.zsh`") — done; `modules/features/secrets.nix:130-186`
    implements the home module and `modules/hosts/gear5th/default.nix:64`
    imports it. Remove or mark done.
  - "First things to validate on gear5th" → the provider-keys bullet still says
    to drop keys in `~/.config/zsh/secrets.zsh` and calls sops a planned
    follow-up. Repoint to the sops home module and
    `~/.config/pi-provider-keys.env`.
- `modules/features/dotfiles.nix` header comment: "Chopper still uses its manual
  `~/.dotfiles` clone until it migrates to this module (phase 2)." — stale;
  chopper consumes this module.

Verification: `grep -rn "until chopper migrates\|secrets.zsh\|planned follow-up"`
returns nothing relevant; no eval/build needed (docs + comment only).

### Slice 2 — Centralize the host user identity

Today `ejverat` is a literal in 5 feature modules plus the host files:

```
modules/features/engram.nix:9      user = "ejverat";
modules/features/gentle-pi.nix:18  user = "ejverat";
modules/features/secrets.nix:114   owner = "ejverat";
modules/features/zsh.nix:12        users.users.ejverat.shell = myZsh;
modules/features/docker.nix:11     users.users.ejverat.extraGroups = [ "docker" ];
```

Design (mirrors the existing `nixosConf.zsh.wrapper` option pattern):

- New `modules/options.nix` exporting `flake.nixosModules.nixosConf`, declaring
  `options.nixosConf.user.name` (`lib.types.str`, no default → a NixOS config
  that imports a feature module without it fails loudly). The home directory is
  **derived**, not a second option: `config.users.users.${name}.home`.
- `modules/hosts/chopper/configuration.nix`: import
  `self.nixosModules.nixosConf`, set `nixosConf.user.name = "ejverat";`, and
  drive `users.users.${...}` and `home-manager.users.${...}` from it so the
  account declaration and the features share one source.
- Consumers read `config.nixosConf.user.name`:
  `gentle-pi.nix` (`user`/`homeDir`), `engram.nix` (`user`/`homeDir`),
  `secrets.nix` (`owner`), `zsh.nix` (shell), `docker.nix` (extraGroups).
- Home-manager modules are untouched: they already use
  `config.home.username` / `config.home.homeDirectory`.

Deliberately left literal: the `home.username` / `home.homeDirectory` values in
each host's home config, because home-manager requires them to match the
attribute key and they are part of the account definition, not of a feature.

Verification: both baseline drv paths must still evaluate; the chopper toplevel
drv path must be **identical** to the baseline (pure literal → option rename).

### Slice 3 — Flake eval checks for both hosts

New `modules/checks.nix` (flake-parts module, no host-specific code):

```nix
{ self, ... }: {
  perSystem = { pkgs, ... }: {
    checks.chopper-eval = pkgs.runCommand "check-chopper-eval" {} ''
      echo "${self.nixosConfigurations.chopper.config.system.build.toplevel.drvPath}" > $out
    '';
    checks.gear5th-eval = pkgs.runCommand "check-gear5th-eval" {} ''
      echo "${self.homeConfigurations.gear5th.activationPackage.drvPath}" > $out
    '';
  };
}
```

The `runCommand` interpolates only the drv path, so the check **forces deep
evaluation** of each host without building the system. `nix flake check` then
guarantees both hosts still evaluate, closing the class of failure already hit
once (a shared home module that breaks the other host's eval).

Risk to verify: flake-parts self-reference recursion when `self.<output>` is
read from inside `perSystem`. If it recurses, the fallback is a top-level
`flake.checks.${system}.*` definition (still in this module) or referencing the
configs through `config.flake`. Confirm with `nix flake check --no-build`.

## Verification (whole feature)

1. `nix flake check --no-build --keep-going` → passes and now lists
   `checks.x86_64-linux.chopper-eval` and `checks.x86_64-linux.gear5th-eval`.
2. `nix eval --raw .#nixosConfigurations.chopper.config.system.build.toplevel.drvPath`
   equals the baseline after every slice.
3. `nix eval --raw .#homeConfigurations.gear5th.activationPackage.drvPath`
   equals the baseline.
4. Optional but recommended before merge: `nix build
   .#nixosConfigurations.chopper.config.system.build.toplevel` and `nix build
   .#homeConfigurations.gear5th.activationPackage` (build, not switch).
5. On-hardware activation stays the user's decision (`nixos-rebuild switch` /
   `home-manager switch`), out of this plan.

## Risks and decisions

- **Slice 2 attribute interpolation**: `users.users.${name}` and
  `home-manager.users.${name}` must agree. Eval catches any mismatch.
- **Slice 3 recursion**: the only real uncertainty; verification step 1 settles
  it, with the documented fallback.
- **Commit/PR shape**: one feature branch, one work-unit commit per slice. The
  batch is well under the 400-line review threshold; split into chained PRs only
  if the reviewer prefers.

## Commit identities

- [ ] Slice 1 — `docs: align README and dotfiles comment with the shared layer`
- [ ] Slice 2 — `refactor(hosts): declare the desktop user once as nixosConf.user.name`
- [ ] Slice 3 — `ci(flake): add eval checks for chopper and gear5th`

## Status

- [ ] Slice 1 — docs drift
- [ ] Slice 2 — host identity option
- [ ] Slice 3 — flake eval checks
