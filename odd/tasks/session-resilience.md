# Feature: session resilience — supervised shell, guarded kanshi, coredumps

## Goal

Stop the failure mode where a single silent crash of the **noctalia shell**
leaves the whole desktop without UI until the session is restarted, and stop
the **kanshi** restart storm on gear5th. Turn on **systemd-coredump** so the
next silent crash leaves evidence instead of disappearing.

## Context discovered

- niri and noctalia are separate layers. When the user reported "niri and
  noctalia closed", `niri` (PID 3254, started 2026-10-02 11:28:41) was still
  running with windows mapped and the output active. Only the noctalia shell
  process (`quickshell -p .../share/noctalia-shell`) was gone.
- The shell was launched **once** by niri:
  `"spawn-at-startup" ".../noctalia-shell"` (line 1 of the generated
  `niri-config.kdl`). niri never re-runs `spawn-at-startup`, so a shell exit is
  permanent until the session restarts — there is no supervisor.
- Evidence of the silent death: the noctalia systemd scope stayed `active` only
  because an orphaned child `nmcli -t monitor` survived (reparented to
  systemd). Last shell cache write 13:34:49; dead by ~13:38, in the same window
  as the Bluetooth headset setup. No coredump and no segfault were recorded.
- `systemd-coredump` is **not installed** on gear5th (`coredumpctl` not found,
  `kernel.core_pattern=core`), so the crash produced no evidence.
- `kanshi.service` has been crash-looping since session start (2026-10-02
  11:28:46), restart counter **16022**, `failed to parse config file`: gear5th
  leaves `nixosConf.kanshi.config = null`, so `~/.config/kanshi/config` is
  never written and the unit has no guard.
- Shared-module constraint: `myNiri` is one baked package used by **both**
  hosts (`self.nixosModules.niri` on chopper, `self.homeModules.niri` on
  gear5th), and chopper deliberately does **not** import
  `self.homeModules.noctalia`. Any move of the shell launch must keep chopper
  working unchanged.

## Decisions

- **kanshi: `ConditionPathExists=%h/.config/kanshi/config`** on the user unit.
  gear5th keeps the config user-owned by design, so when it is absent the unit
  is skipped instead of failing; chopper has the config and is unaffected. This
  removes the restart storm without disabling the daemon.
- **noctalia: a supervisor, not the launcher.** niri keeps its
  `spawn-at-startup`; `noctalia-shell.service` revives the shell after a crash.
- **Do not touch the niri package.** An earlier `myNiriSupervised` split
  changed `niri.service` and a live switch made `sd-switch` restart the
  compositor (`R4-niri-switch-session-loss`). gear5th keeps `myNiri`.
- **coredump belongs to the Debian system layer**, not the flake: add
  `systemd-coredump` to `scripts/debian-system-services.sh` and enable
  `systemd-coredump.socket` there. It needs `sudo`, so it is applied by the
  user running the script (repo agent rule 1 keeps home-manager non-sudo).

## Tasks

1. Guard `kanshi.service` with `ConditionPathExists` (`modules/features/kanshi.nix`).
2. Keep the niri package untouched: gear5th keeps `myNiri`, so `niri.service` matches the base (`modules/features/niri.nix`).
3. Add a `noctalia-shell.service` supervisor that revives the shell the compositor spawned (`modules/features/noctalia.nix`).
4. Add `systemd-coredump` to the Debian system layer + report (`scripts/debian-system-services.sh`).
5. Document the supervised shell and the failure-catalog entry (`docs/gear5th-support.md`).
6. Verify: `nix flake check` (both hosts eval), `home-manager build`, activate, runtime probes.
7. Commit each work unit.

## Risks

- The niri package split changes store paths for the niri wrapper and its
  `niri.service` unit on gear5th; `home-manager switch` will rewrite
  `~/.config/systemd/user/niri.service` and `ExecReload`. A session restart is
  needed for niri itself to pick up the new wrapper, but the **shell unit
  starts immediately** under the current session.
- The systemd-coredump step cannot run from this agent: `sudo` requires a
  password (repo agent rule 1/3). The user runs
  `./scripts/debian-system-services.sh` (or the one-liner recorded below).
- Two shells must not run at once: the manually re-spawned noctalia from the
  incident response must be stopped before activating the unit.

## Verification evidence

Build and evaluation (branch `fix/session-resilience`):

- `nix flake check --no-build` -> 0.
- `nix build .#checks.x86_64-linux.gear5th-eval .#checks.x86_64-linux.chopper-eval`
  -> 0: both hosts still evaluate, and chopper keeps its spawn (it does not
  import `homeModules.noctalia`).
- gear5th's `niri.service` points at the base store path
  (`.../l4w04...-niri-26.04/bin/niri`), so a switch does not touch the
  compositor.
- `home-manager switch --flake .#gear5th` -> exit 0.

Runtime, after activation (2026-10-06, current session):

- `noctalia-shell.service` (the supervisor) active under
  `graphical-session.target`; niri still spawns the first shell.
- Supervision test: `kill -9` on the shell -> the supervisor starts a new one
  within a few seconds.
- `kanshi.service` inactive (dead), `ConditionResult=no`, `NRestarts=0` — the
  16k-restart loop is gone; the daemon still starts normally if the user
  creates `~/.config/kanshi/config`.
- `niri` PID unchanged across the switch (2572): no session restart.

Still pending (needs `sudo`; the agent cannot run it):

- `./scripts/debian-system-services.sh` installs `systemd-coredump`. Until it
  runs, `--check` reports `core_pattern is 'core'` and a crash leaves no trace.

Incident during verification: the first switch restarted niri (`sd-switch` saw
`niri.service` change between gen 35 and 36) and killed the activation before
it wrote its gcroot. The review raised it as `R4-niri-switch-session-loss`
(CRITICAL); the correction reverts gear5th to `myNiri`.

## Commit identities

- `eae9beda78a1983fef8e818e31c2307dbc896fcf` docs(odd): open the session-resilience feature
- `994a9a273523f985de61ea87e3b1a392e2b35810` fix(kanshi): skip the daemon when no config is present
- `bedf0e1b0b72191bb217cbacbee432b62e4aeb01` feat(noctalia): supervise the shell with a systemd user unit
- `f563163edfd9d1d8bc76480861f5edd164925cdf` feat(gear5th): enable systemd-coredump in the system layer
- `bc981d18ca2daf527c78f9505f89eb5eac9d4d77` docs(gear5th): document the supervised shell and coredumps
- _this commit_: docs(odd): close session resilience
