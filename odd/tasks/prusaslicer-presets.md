# Feature: share PrusaSlicer presets with chopper

## Goal

Give chopper the same PrusaSlicer presets gear5th has, so the second host does
not start with an empty slicer. Mirrors what was done for OrcaSlicer in #40: the
application plus the seed. The `push`/`pull` script for PrusaSlicer is
deliberately **not** part of this change — it is the next step in the agreed
order.

## Context discovered

**chopper is clean.** `modules/hosts/chopper/configuration.nix` has no reference
to PrusaSlicer or Flatpak, so this is a fresh install with no configuration to
preserve. Its shape for OrcaSlicer is the one to mirror: the application comes
from `self.nixosModules.orcaslicer` (NixOS, `environment.systemPackages`) while
the presets come from `self.homeModules.orcaslicer-presets` (home). Neither
`homeModules.orcaslicer` nor a GTK module of its own is needed there — chopper
already imports `self.homeModules.gtk`.

**What is shareable on gear5th** (measured after the application had been used,
so these are real post-run numbers):

| Path | Files | Share |
| --- | --- | --- |
| `printer/` | 1 (8 K) | yes |
| `print/` | 3 (28 K) | yes |
| `filament/` | 2 (12 K) | yes |
| `physical_printer/` | 1 (8 K) | yes |
| `sla_print/`, `sla_material/`, `vendor/`, `shapes/` | 0 | nothing to share |
| `cache/` | 112 (4.8 M) | no — derived, and the application rebuilt it on first launch |
| `workflows.json`, `PrusaSlicer.ini`, `ArchiveRepositoryManifest.json` | — | no — application state, not presets |

The seven preset files were **not** touched by the first launch (their mtimes are
from August–October 2025), only the derived state was created. So the presets are
stable user content and the seed policy can be the same one OrcaSlicer uses.

**A caveat specific to these presets.** The printer preset references two local
assets by absolute path:

```
bed_custom_model   = ~/LDATA/3DPrint/KP3SProS1/Configs/KP3S-Prusa-main/Kingroon/pros1_bed.stl
bed_custom_texture = ~/LDATA/3DPrint/KP3SProS1/Configs/KP3S-Prusa-main/Kingroon/kp3s-alt1.svg
```

Both exist on gear5th. On a host without them PrusaSlicer will simply not render
the custom bed — it is optional, not fatal — but this is worth recording rather
than discovering later as a mystery. Vendoring those two assets is out of scope;
they belong to `~/LDATA`, not to this repository.

## Decisions

- **Vendor under `dotfiles/prusaslicer/presets/`**, mirroring the destination
  layout (`presets/printer/…` becomes `<config>/printer/…`). PrusaSlicer has no
  `user/default` level the way OrcaSlicer does, so the intermediate name says
  what the tree is rather than imitating a path that does not exist.
- **Generalise the shared seed body instead of duplicating it.** The current
  `modules/lib/_orca-presets.nix` hardcodes OrcaSlicer's destination, so it
  becomes `modules/lib/_preset-seed.nix` taking a `destination` argument, and both
  preset features import it. Duplicating 40 lines of shell for a second
  application would be the wrong trade.
- **Same seed policy**: copy only what is missing, never overwrite, so a preset
  edited in the GUI always wins. That is what makes it safe on every activation.
- **No GTK work**, no pin work, no new package module: `flake.nixosModules.prusaslicer`
  and `flake.homeModules.prusaslicer` already exist from the previous change.

## Tasks

1. Vendor the seven preset files into `dotfiles/prusaslicer/presets/`.
2. Rename `modules/lib/_orca-presets.nix` to `_preset-seed.nix` with a
   `destination` parameter, and update the OrcaSlicer feature to pass its own.
3. Add `modules/features/prusaslicer-presets.nix`.
4. Register the seed on gear5th.
5. Onboard chopper: `nixosModules.prusaslicer` plus `homeModules.prusaslicer-presets`.
6. Build gear5th, evaluate chopper, and verify the seed lands in both.
7. Commit and ship through the issue-first PR flow.

## Risks

- **The rename touches merged code.** `_orca-presets.nix` and its one consumer
  are already in `main`; the change is mechanical but it does mean this PR edits
  the OrcaSlicer feature as well as adding PrusaSlicer's. Justified because the
  alternative is duplicating the seed logic.
- **The bed assets are not in the repository**, so chopper gets presets whose
  custom bed silently will not render. Documented, not fixed.
- Preset files are `.ini` here, unlike OrcaSlicer's JSON with `.info` sidecars, so
  the tree is flat per directory and the seed body must not assume OrcaSlicer's
  structure. The generalised body is path-agnostic, which handles this.

## Verification evidence

Vendoring:

- 7 files / 60 K into `dotfiles/prusaslicer/presets/` — `printer/` 1, `print/` 3,
  `filament/` 2, `physical_printer/` 1. `diff -r` against the live directories is
  identical for all four.

Generalisation, and the regression check that matters:

- `git mv` recorded the library rename, so history is preserved
  (`R modules/lib/_orca-presets.nix -> modules/lib/_preset-seed.nix`).
- gear5th's generated activation contains **both** hooks, `orcaPresetSeed` and
  `prusaPresetSeed`, resolving to
  `~/.config/OrcaSlicer/user/default` and `~/.config/PrusaSlicer` respectively.
  OrcaSlicer's destination and policy are therefore unchanged by the rename —
  that was the risk of touching merged code, and it is checked rather than
  assumed.
- `nix build .#homeConfigurations.gear5th.activationPackage` succeeds and
  `prusa-slicer` 2.9.6 is still in the profile.

chopper:

- `nixosConfigurations.chopper.config.system.build.toplevel.drvPath` evaluates.
- Its `environment.systemPackages` now carries both `prusa-slicer-2.9.6` and
  `orca-slicer-2.4.2`.
- Both seed hooks reach chopper's home activation with the same two destinations,
  so the presets land there through the same mechanism as OrcaSlicer's rather
  than a second one.

Behaviour worth stating plainly: the seed is a **no-op on gear5th**, because all
seven files already exist there — that is the "only when missing" policy working
as intended. On chopper, which is clean, it is what fills the directories.

## Bed assets: fetched from upstream, not vendored

The vendored printer preset references two bed assets by absolute path, so
shipping the preset alone leaves a preset whose custom bed silently does not
render — which is why this was added before testing on chopper rather than after
someone noticed an odd-looking bed.

They are **not the user's work**. They come from `github.com/RyanT95/KP3S-Prusa`,
distributed under **Creative Commons Attribution-NonCommercial 4.0
International**, and this repository is public, so vendoring them would mean
republishing third-party material. They are fetched from a pinned upstream
revision instead:

```
rev  = 2b5f86f2e7e1e9a345c5da91f400604e3778cdef
hash = sha256-XcqaaZIIBws7yCokc24kKzZIfkKtWZ4F7oPFO3ez7+0=
```

That keeps third-party content out of the repository, leaves the licence and the
provenance with the source they belong to, and makes the exact revision
auditable. Only the two referenced files are extracted, so nothing else from the
bundle lands on disk.

The revision was chosen after checking that both assets there are
**byte-identical** to the copies already in use on gear5th — `956dd6c7…` for the
STL and `31b5fad6…` for the SVG — so this cannot change the bed being sliced
against. That was verified against the built store path, not inferred from the
revision date.

**Destination: inside the config directory.** The assets live in
`~/.config/PrusaSlicer/bed-assets/`, so the whole PrusaSlicer setup stays in one
place instead of reaching into the user's `~/LDATA` tree.

**They are linked, not seeded**, and the split is deliberate: the presets are
mutable runtime state the application rewrites, so they are seeded and never
overwritten, while the assets are read-only inputs the application only ever
reads, so `home.file` links them and they cannot drift from the pinned revision.

**Moving them meant repointing the presets**, and not only the repository copies.
Because a preset references them by absolute path and the seed never overwrites,
editing only the vendored copy would have left the host still reading the old
location. Both the vendored and the live preset were changed together, and the
old path no longer appears anywhere under the config directory.

That absolute path embeds the user name. Fine here, because both hosts run the
same account; a host with a different one would need its preset repointed.

An earlier revision of this change generalised the seed body to accept a *list* of
`{ src, dst }` pairs so it could place the assets too. Once the assets moved to
`home.file` that generality had no consumer, so the body went back to a single
pair rather than keeping machinery that had lost its justification.

## Follow-ups

- ~~Extend the `push`/`pull` script to PrusaSlicer~~ — done, by generalising it
  rather than patching it: `scripts/orca-presets.sh` became
  `scripts/slicer-presets.sh <tool> <action>`. See
  `odd/tasks/slicer-presets-script.md`.
- Remove the PrusaSlicer Flatpak on gear5th once the native build is trusted.
- FreeCAD is the remaining application in the backlog item.
