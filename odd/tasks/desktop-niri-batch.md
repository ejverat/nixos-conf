# Feature: desktop niri batch (hyprpicker + kanshi)

## Goal

Port the roadmap's first desktop group to the shared layer so chopper and
gear5th use one mechanism.

## Decisions

- **hyprpicker**: converted to a **home-only** module
  (`flake.homeModules.hyprpicker`). chopper dropped
  `flake.nixosModules.hyprpicker` (it only installed the same package
  system-wide) and now imports the home module like gear5th.
- **kanshi**: converted to a shared home module with the config as an option.
  - `nixosConf.kanshi.config` (`nullOr lines`, default `null`).
  - **Declared** on chopper (its laptop + dock profiles: HDMI-A-1 + eDP-1) ->
    written to `~/.config/kanshi/config`.
  - **Left unset** on gear5th -> the module still installs the package and the
    user service, and the config stays user-owned runtime state at
    `~/.config/kanshi/config`, like the OrcaSlicer presets or `~/.pi`. This is
    the chosen approach: gear5th is a fixed-monitor desktop whose outputs are
    not documented anywhere, so Nix does not guess them.
  - Both hosts run the same `kanshi.service` systemd user unit, with
    `ExecStart` = kanshi's default config path (no `-c /etc/kanshi/config`).
  - Removing `flake.nixosModules.kanshi` means chopper's kanshi config moved
    from `/etc/kanshi/config` to `~/.config/kanshi/config`; the profiles are
    unchanged.

## Tasks

1. [x] hyprpicker -> home-only module, imported on both hosts.
2. [x] kanshi -> shared home module with a per-host config option.

## Verification evidence

hyprpicker:
- `hyprpicker-0.4.7` in `home.packages` of both hosts.
- **absent** from chopper's `environment.systemPackages` (migration took effect).

kanshi:
- `kanshi-1.9.0` in `home.packages` of both hosts.
- chopper: `xdg.configFile` includes `kanshi/config` and
  `systemd/user/kanshi.service`; generated config text is the laptop + dock
  profiles.
- gear5th: `kanshi/config` is **not** in `xdg.configFile` (user-owned), while
  `systemd/user/kanshi.service` is still installed.

Both:
- `nix build` of both host configurations -> exit 0.
- `nix flake check --no-build` -> all checks passed.

## Commit identities

- [x] `feat(desktop): share hyprpicker through the home layer` (49cb2d4)
- [ ] `feat(desktop): share kanshi through the home layer with per-host config`
