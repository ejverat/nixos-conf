# Feature: desktop niri batch (hyprpicker + kanshi)

## Goal

Port the roadmap's first desktop group to the shared layer so chopper and
gear5th use one mechanism: `hyprpicker` and `kanshi`.

## Decisions

- **hyprpicker** (done): converted to a **home-only** module
  (`flake.homeModules.hyprpicker`). chopper dropped
  `flake.nixosModules.hyprpicker` (it only installed the same package
  system-wide) and now imports the home module like gear5th.
- **kanshi** (pending decision): its profiles are chopper-specific — they
  describe the *laptop + dock* scenario (HDMI-A-1 1920x1080 + eDP-1
  1366x768). gear5th is a **desktop** (AMD RX 580) whose outputs are not
  documented anywhere (not in the repo, not in the `archive/debian-migration-draft`
  tag, which carries the same chopper profiles). A fixed-monitor desktop
  normally gains nothing from kanshi.
  - Option A: leave kanshi chopper-only (least risk; the system module stays as
    validated on hardware).
  - Option B: make it a shared home module with the profile text as a
    `nixosConf` option, migrating chopper and adding gear5th once its
    `niri msg outputs` are known.

## Tasks

1. [x] hyprpicker -> home-only module, imported on both hosts.
2. [ ] kanshi -> decide A or B.

## Verification evidence (hyprpicker)

- `hyprpicker-0.4.7` in `home.packages` of both hosts.
- `hyprpicker` **absent** from chopper's `environment.systemPackages` (migration
  took effect).
- `nix build` of both host configurations -> exit 0.
- `nix flake check --no-build` -> all checks passed.

## Commit identities

- [ ] `feat(desktop): share hyprpicker through the home layer`
