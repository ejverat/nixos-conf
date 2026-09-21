# Feature: generalise the preset sync script

## Goal

One script that keeps vendored slicer presets and the live application
directories in sync, for **both** OrcaSlicer and PrusaSlicer, instead of an
OrcaSlicer-only script plus either a copy or an awkward patch for the second tool.

## Context discovered

`scripts/orca-presets.sh` works and is documented, but everything about it is
hardcoded to one application. The parts that differ between tools are exactly
three:

| | OrcaSlicer | PrusaSlicer |
| --- | --- | --- |
| Vendored tree | `dotfiles/orcaslicer/user-default` | `dotfiles/prusaslicer/presets` |
| Live directory | `<config>/OrcaSlicer/user/default` | `<config>/PrusaSlicer` |
| Preset shape | JSON with `.info` sidecars under `user/default/<kind>/` | flat `.ini` files under `<kind>/` |

Everything else — `status`, `push`, `pull`, the NUL-delimited file lists, the
`--dry-run` handling, the backup before overwriting — is identical. Note that the
preset *shape* never enters the logic: the script walks the vendored tree and
mirrors it, so it is already structure-agnostic.

Adding PrusaSlicer support to a file named `orca-presets.sh` would make the name a
lie, which is the same reasoning that kept the `nixpkgs-orca` pin out of the
PrusaSlicer package change. Duplicating 130 lines was the alternative, and it is
worse.

## Decisions

- **One script, `scripts/slicer-presets.sh <tool> <action>`, with `tool` being
  `orca` or `prusa`.** The per-tool differences live in a single lookup, so a
  third tool later is a two-line addition.
- **`scripts/orca-presets.sh` is removed rather than kept as a shim.** A shim
  would be residue kept only to avoid editing documentation, and the documented
  interface changes in the same change that renames it. The README and the code
  comments that name the script are updated; the historical trackers keep their
  original wording, because rewriting them would falsify the record of what was
  done at the time, and they get a pointer to the new name instead.
- **A neutral `SLICER_DATA_DIR` replaces `ORCA_DATA_DIR`.** One override for both
  tools beats one per tool.
- **The backup moves to the state directory**, to
  `~/.local/state/slicer-presets-backups/<tool>/<timestamp>/` (honouring
  `XDG_STATE_HOME`). It used to land inside the application's directory as
  `user_backup-presets.<timestamp>`, echoing OrcaSlicer's own `user_backup-*`
  convention. That convention does not exist for PrusaSlicer, and keeping the
  backup inside the data directory is actually wrong for it: PrusaSlicer's presets
  sit at the root of its config directory, so `DEST` and `DATA_DIR` are the same
  path and the backup is copied **into itself**. Moving it out removes the hazard
  for every tool instead of special-casing one, and neither application ever sees
  it. This is the bug the scratch run caught, and only for the new tool — see the
  evidence.
- **`--dry-run` semantics unchanged**, and `pull` still never deletes a file that
  exists only on the live side.

## Tasks

1. Add `scripts/slicer-presets.sh` with a per-tool lookup.
2. Remove `scripts/orca-presets.sh`.
3. Update the README and the code comments that name the old script.
4. Point the historical trackers at the new name without rewriting their history.
5. `shellcheck`, plus a scratch run for **both** tools, since the OrcaSlicer path
   is a regression risk of this change.
6. Commit and ship through the issue-first PR flow.

## Risks

- **The OrcaSlicer path must not regress.** It is the validated one and the tool
  in daily use, so the scratch verification covers both tools, not just the new
  one.
- **The interface changes.** Anyone with `./scripts/orca-presets.sh` in muscle
  memory or in a private alias will get a missing file; the README carries the new
  invocation.

## Verification evidence

`shellcheck scripts/slicer-presets.sh` is clean, and the argument handling was
checked by hand: no arguments, a tool without an action, and an unknown token all
exit 2 with a message rather than doing something surprising.

Behaviour was then exercised on scratch trees for **both** tools — the vendored
trees copied into a temp repository, the live directories under a temp config home,
and `XDG_STATE_HOME` redirected so nothing real was touched:

| Step | orca | prusa |
| --- | --- | --- |
| `status` on an empty tree | only in repo: 56 | only in repo: 7 |
| `pull` | 56 files applied | 7 files applied |
| `status` afterwards | up to date: 56 | up to date: 7 |
| edit one live file | 55 / differ: 1 | 6 / differ: 1 |
| `push --dry-run` | reports 1, repo untouched | reports 1, repo untouched |
| `push` | captured, repo now matches | captured, repo now matches |
| `pull` after a repo change | applied, backup created | applied, backup created |
| backup contents | 56 files, outside the app dir | 7 files, outside the app dir |
| `pull --dry-run` | reports, writes nothing | reports, writes nothing |

**The scratch run found a real bug, and only for the new tool.** With the backup
inside the application's directory, PrusaSlicer — whose presets live at the root of
its config directory, so `DEST == DATA_DIR` — produced:

```
cp: cannot copy a directory '…/config/PrusaSlicer/.' into itself,
    '…/config/PrusaSlicer/presets-backup.…'
```

OrcaSlicer was unaffected because its preset subtree sits one level deeper. This is
precisely why the verification had to cover both tools rather than only the newly
supported one, and why "the script is a mechanical generalisation" was a claim
worth testing instead of assuming.

## Follow-ups

- Removing the PrusaSlicer Flatpak on gear5th, then FreeCAD.
