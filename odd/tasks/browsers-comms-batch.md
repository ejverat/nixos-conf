# Feature: browsers/comms batch (chromium, google-chrome, slack, teams)

## Goal

Port the roadmap's browsers/comms group to the shared layer so chopper and
gear5th use one mechanism.

## Decisions

- Each app becomes a **home-only** shared module (`flake.homeModules.chromium`,
  `.google-chrome`, `.slack`, `.teams`). The old `flake.nixosModules.*` only
  installed the same package system-wide, so they are removed.
- chopper drops those four `nixosModules` imports and now imports the home
  modules, like gear5th.
- `google-chrome` is unfree; evaluation succeeds because `allowUnfree` is
  enabled both by the flake-level pkgs (`modules/lib/_pkgs.nix`, used by gear5th
  standalone) and by chopper's `nixpkgs.config.allowUnfree`.
- `teams` installs `pkgs.teams-for-linux`.

## Tasks

1. [x] Convert the four feature files to home-only modules.
2. [x] Import them on both hosts; drop the chopper `nixosModules` imports.

## Verification evidence

- In `home.packages` of **both** hosts:
  `chromium-152.0.7977.64`, `google-chrome-152.0.7977.75`, `slack-4.51.180`,
  `teams-for-linux-2.17.1`.
- All four **absent** from chopper's `environment.systemPackages` (migration
  took effect).
- `nix build` of both host configurations -> exit 0 (no `buildEnv` path
  conflict between chromium and google-chrome).
- `nix flake check --no-build` -> all checks passed.

## Commit identities

- [ ] `feat(desktop): share the browsers/comms apps through the home layer`

## Follow-up batches (roadmap)

media/office (gimp, libreoffice + fonts), files (thunar stack), CLI/dev
(bat, fd, direnv, tree, pciutils, upower).
