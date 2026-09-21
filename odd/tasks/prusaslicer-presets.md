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

(to be filled in as tasks complete)

## Follow-ups

- Extend the `push`/`pull` script to PrusaSlicer. `scripts/orca-presets.sh` is
  OrcaSlicer-specific; the honest move is to generalise it rather than put
  PrusaSlicer handling inside a script named after the other application.
- Remove the PrusaSlicer Flatpak on gear5th once the native build is trusted.
- FreeCAD is the remaining application in the backlog item.
