# Feature: session-safe `home-manager switch` on gear5th

## Goal

Make `home-manager switch` stop tearing down the running niri session on
gear5th, and repair the stale Home Manager gcroots baseline that makes the
teardown repeat on every subsequent switch.

## Problem and context discovered

- 2026-10-18 23:35, the switch that created generation 37 killed the session.
  The user journal shows the exact mechanism:

  ```
  23:35:34 systemd[2485]: Stopping niri.service - A scrollable-tiling Wayland compositor...
  23:35:34 niri[2619]: quitting due to receiving signal SIGTERM
  23:35:34 systemd[2485]: Stopped target graphical-session.target - Current graphical user session.
  ```

- Root cause: commit `22554dc` re-added `spawn-at-startup` to the niri wrapper,
  so `modules/features/niri.nix` produced a new `myNiri` store path. The
  generated `niri.service` changed `ExecStart`, `ExecReload` and
  `X-Reload-Triggers`. Home Manager activation applies unit changes with
  `sd-switch`, and for an active changed service the default method is
  `stop-start`, so it stopped the compositor. `niri.service` has
  `BindsTo=graphical-session.target`, so stopping it stopped the whole session
  and dropped the user to tty.

- Aggravating, self-perpetuating state: `~/.local/state/home-manager/gcroots/current-home`
  still points at generation 36 while generation 37 is the active one. The
  activation was killed before its last step, and Home Manager diffs against
  `gcroots/current-home`, not the profile symlink. Every later switch therefore
  diffs generation 36 against the new one and repeats the same restart. This is
  the same failure documented in `odd/tasks/gear5th-session-gtk.md`.

- Mechanism confirmed in `sd-switch` 0.6.4 source (`src/lib.rs`,
  `src/unit_file.rs`, `src/systemd/ini.rs`):
  - the switch method is read from the **new** unit file
    (`new_unit_file.switch_method()`);
  - `[Unit] X-SwitchMethod=keep-old` maps to `UnitAction::KeepOld`, which does
    nothing to the running unit;
  - the directive may also come from a `*.d/overrides.conf` drop-in next to the
    new unit file (`collect_overrides`).

## Decisions

- **`X-SwitchMethod=keep-old` for `niri.service`**, delivered as a managed
  drop-in `~/.config/systemd/user/niri.service.d/overrides.conf`. A compositor
  cannot be hot-swapped anyway: the new binary and config take effect at the
  next session start, and a live switch no longer touches the running session.
- **Keep the unit file itself a symlink to the package unit.** The drop-in adds
  a directive; it does not duplicate or fork the upstream unit definition.
- **Repair `gcroots/current-home`** as an operational step, so the next diff has
  the right baseline. Not a repo change.
- **Do not revert the niri wrapper change from `22554dc`.** The `keep-old`
  directive removes the coupling between "the niri wrapper changed" and "the
  session dies" without giving anything up.
- **Only `niri.service` gets `keep-old`.** The `noctalia-shell` supervisor,
  `kanshi`, `lan-mouse` and `sops-nix` may be restarted safely.

## Scope and non-goals

In scope: `modules/features/niri.nix` (home module only) and the gear5th
operations docs.

Non-goals: changing `myNiri`, touching `flake.nixosModules.niri` (chopper),
disabling the noctalia supervisor, adding a stable `ExecStart` indirection
(deferred: it would duplicate the upstream unit; `keep-old` is smaller and
sufficient), changing Home Manager's global `startServices` setting.

## Constraints

- `myNiri` is one baked package shared by both hosts: chopper uses
  `flake.nixosModules.niri`; only gear5th uses `flake.homeModules.niri`, so the
  drop-in must live in the home module and must not affect chopper.
- `xdg.configFile` writes into the generation's `home-files`, which is exactly
  the directory `sd-switch` diffs, so the drop-in is visible to it.
- Real systemd also reads the drop-in; `X-SwitchMethod` is a Home Manager /
  sd-switch extension, so systemd logs it as an unknown key and ignores it.
  Home Manager's own generated units carry the same directive, so this is the
  established ecosystem behavior.

## Resolved checks

- TDD: **off**. Source: repository evidence — this repo has no unit-test runner
  for Nix module changes, and none of its existing features (including
  `session-resilience`) used one. Checks are functional: flake evaluation, a
  build of the activation package, an `sd-switch --dry-run` plan diff, and
  runtime probes.

## Tasks

| ID | Task | Route |
|----|------|-------|
| A1 | Add the `niri.service` keep-old drop-in in `flake.homeModules.niri` | inline (one mechanical, already-understood file; writer trigger not fired) |
| A2 | Repair `gcroots/current-home` to the active generation and remove a stale `new-home` if present | inline (parent-owned operational state) |
| A3 | Build the gear5th activation package and preview the exact `sd-switch` plan with `--dry-run` | inline (bounded check) |
| A4 | Apply the switch, confirm niri's PID is unchanged, confirm the gcroots rename completed | inline, with explicit user go-ahead for the session-affecting moment |
| A5 | Document the mechanism and the operational rule in `docs/gear5th-support.md`; commit the work unit | inline |

## Acceptance criteria

1. `home-manager switch` completes with `niri.service` PID unchanged.
2. `sd-switch --dry-run` for the new generation lists `niri.service` as
   "Keep active" (no restart/stop).
3. `gcroots/current-home` resolves to the active generation after the switch.
4. The running compositor is untouched; the new wrapper applies at the next
   session start.
5. chopper still evaluates (`nix flake check`).

## Risks

- If the directive were read from the old unit, the applying switch would still
  restart niri. Verified against sd-switch 0.6.4 source that it reads the new
  unit; A3's dry-run is the empirical confirmation before A4.
- A stale baseline combined with a changed `niri.service` is the failure mode
  being fixed; A2 removes the stale baseline first.
- `systemd` may log `X-SwitchMethod` as an unknown key on `daemon-reload`.
  Cosmetic, same as Home Manager's own units.

## Progress

- A1 done: drop-in added to `flake.homeModules.niri`
  (`modules/features/niri.nix`), written as one escaped line because Nix's
  indented-string stripping counts only spaces and a `''` block would ship the
  leading tabs into the fragment.
- A2 done: `gcroots/current-home` repaired from generation 36
  (`q3nfcglw4kjcikixqphkrpim9qjgmvrg`) to the active generation 37
  (`dv084q4daggcl83c7q9rgkrpdidqb9rw`); no stale `new-home` existed.
- A3 done: built the activation package and previewed the apply plan.
- A4 done: applied with `home-manager switch --flake .#gear5th`, exit 0.
- A5 done in this commit.

## Verification evidence

- Evaluated drop-in content (exact bytes, `cat -A`): `[Unit]$` /
  `X-SwitchMethod=keep-old$`.
- `nix build .#homeConfigurations.gear5th.activationPackage` ->
  `/nix/store/sk3vgl8knbwhvh5scxpvlgk8rf320v2z-home-manager-generation`.
- `sd-switch --dry-run --user --old-units <gen37>/home-files/.config/systemd/user
  --new-units <new>/home-files/.config/systemd/user`:

  ```
  Performing dry-run
  Keeping old units: niri.service
  Starting units: kanshi.service, sops-nix.service
  ```

  `niri.service` is reported under "Keeping old units" even though the unit
  file itself is byte-identical: the new generation's drop-in changes the merged
  config, so the new unit's `X-SwitchMethod=keep-old` is what decides, which is
  exactly the property the fix relies on.
- Applied switch output included `Keeping old units: niri.service` and no niri
  stop/restart.
- `niri.service` `MainPID` before and after: `187709` / `187709` (unchanged).
- After the switch, `gcroots/current-home` and the `home-manager` profile both
  resolve to `sk3vgl8knbwhvh5scxpvlgk8rf320v2z-home-manager-generation`, so the
  baseline is no longer stale.
- Pending: `nix flake check` for the chopper side is run with the feature B
  work unit.

## Commit identities

- _this commit_: fix(niri): keep the compositor alive across a home-manager
  switch

## Next step

Feature B: bump pi and gentle-shell (see `odd/tasks/gentle-shell-v4.md`).
