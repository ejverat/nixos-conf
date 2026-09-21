# Feature: share OrcaSlicer user presets between gear5th and chopper

## Goal

Keep the user's OrcaSlicer print profiles in one place, versioned in this
repository, so chopper can get the same presets without manual copying — and so
edits made in the GUI can be captured back deliberately.

## Context discovered

OrcaSlicer's data directory (`~/.config/OrcaSlicer`) is **mutable runtime state
the application writes to**: new presets, edits, an instance lock, caches. Store
paths are read-only, so it cannot be modelled with `home.file` or
`xdg.configFile` — the same reason `~/.pi` and this directory were deliberately
left out of the `dotfiles` module. Sharing therefore needs a **seed or a sync**,
never a symlink into the store.

What is actually worth sharing, out of the whole data dir:

| Path | Size | Share |
| --- | --- | --- |
| `user/default/machine/` | 36 K | yes — Klipper printers |
| `user/default/process/` | 44 K | yes — process profiles |
| `user/default/filament/` | 184 K | yes — includes `filament/base/` |
| `.orcaslicer_machine_id` | — | no — per-machine UUID |
| `OrcaSlicer.conf` | 16 K | no — window geometry, recents, last selection |
| `system/` | 3.4 M | no — the app regenerates it from bundled profiles |
| `printers/`, `cache/`, `log/`, `ota/`, `user_backup-*` | — | no — app-managed or transient |

The shareable subset is **56 files / 184 K**: 28 `.json` presets and their 28
`.info` sidecars, which must travel together.

Two facts that shape the design:

- **chopper does not have OrcaSlicer installed.** `modules/hosts/chopper/configuration.nix`
  imports neither `nixosModules.orcaslicer` nor `homeModules.gtk`, so the presets
  have nowhere to land yet. Onboarding chopper is a separate change (it also
  needs the NVIDIA path: chopper is NVIDIA, gear5th is AMD).
- **Both hosts consume the same `nixpkgs-orca` pin**, so both would run exactly
  2.4.2 and the presets' `inherits` chains keep resolving against matching
  system preset names. Pinning is what makes raw presets safe to share.

## Decisions

- **A: seed on activation, only when a file is missing.** Same policy as
  `modules/lib/_gentle-profile.nix`: a runtime-provided file always wins, and the
  activation never overwrites. This is what runs on a fresh host.
- **B: an explicit sync script** (`scripts/orca-presets.sh`) with `status`,
  `push` (live to repo, to capture GUI edits) and `pull` (repo to live, to apply
  repo changes to a host that already has files). Without B, the seed's
  never-overwrite policy would mean repo edits never reach a host that already
  has the file.
- **Vendored under `dotfiles/orcaslicer/user-default/`**, following the existing
  `dotfiles/pi-gentle-ai/` precedent for vendored assets that the app keeps
  editing at runtime.
- **Shared activation body in `modules/lib/_orca-presets.nix`**, with the leading
  underscore so import-tree skips it, following `_gentle-profile.nix`.
- **Only the three preset subtrees are ever touched.** Excluding the machine id,
  `OrcaSlicer.conf`, `system/`, `printers/` and the transient dirs is structural,
  not a filter that could be forgotten.
- **`pull` backs up before overwriting** the live preset tree, and both
  directions support `--dry-run`.

## Tasks

1. Vendor `user/default/{machine,process,filament}` into
   `dotfiles/orcaslicer/user-default/`.
2. Add `modules/lib/_orca-presets.nix` with the shared seed body.
3. Add `modules/features/orcaslicer-presets.nix` (`flake.homeModules.orcaslicer-presets`).
4. Add `scripts/orca-presets.sh` with `status`, `push` and `pull`.
5. Register the module in gear5th.
6. Build, verify the seeding policy and the script against a scratch tree.
7. Document it, then commit and ship through the issue-first PR flow.

## Risks

- Presets reference system preset names through `inherits`. If the two hosts ever
  diverge on the `nixpkgs-orca` pin, profiles can show as based on a missing
  profile. Keep both hosts on the same pin.
- The seed runs on every switch; it must stay idempotent and silent when nothing
  is missing.
- A preset whose name contains spaces and `@` (all of them do) must survive the
  shell body without quoting damage.

## Verification evidence

Vendoring:

- 56 files / 268 K copied into `dotfiles/orcaslicer/user-default/` (28 `.json`
  presets and their 28 `.info` sidecars). `diff -r` against the live data dir
  reports **identico** for `machine`, `process` and `filament`.

Build and wiring:

- `nix build .#homeConfigurations.gear5th.activationPackage` succeeds, and the
  generated activation script contains the `orcaPresetSeed` hook and the seed
  body.

Seed policy, exercised against a scratch `HOME` and a scratch vendored tree:

| Step | Expected | Result |
| --- | --- | --- |
| seed into an empty tree | 56 files | 56 files |
| run again | silent, idempotent | no output |
| run after editing a preset in the "GUI" | the edit survives | preserved |

Sync script, exercised with `REPO_DIR` and `ORCA_DATA_DIR` pointed at scratch
copies so the real repo and the real presets were never touched:

| Step | Expected | Result |
| --- | --- | --- |
| `status` with one edited preset | 55 up to date, 1 differs | 55 / 1 |
| `push --dry-run` | reports 1, writes nothing | reported, repo untouched |
| `push` | captures 1 into the repo | captured |
| `status` after push | 56 up to date | 56 |
| `pull` | applies the repo change | applied |
| `pull` backup | tree copied out of `user/` | `user_backup-presets.<ts>/` created |
| `pull --dry-run` | reports, writes nothing | live file unchanged |
| `shellcheck scripts/orca-presets.sh` | clean | exit 0 |

`shellcheck` initially reported `SC2034` for an unused `SUBDIRS` array: the
script derives its file lists with `find` over the vendored tree, so the array
was dead code and was removed rather than silenced.

## Follow-ups

- Onboard chopper: `nixosModules.orcaslicer` (+ the AMD/NVIDIA GL question) and
  `homeModules.gtk`, then register this module there too.
- The seed covers presets only; a future change could extend it to the printer
  configs if they ever become user-authored.
