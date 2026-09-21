# Feature: native FreeCAD on gear5th (Flatpak to nixpkgs)

## Goal

Run FreeCAD as a Nix-managed package on gear5th instead of the Flatpak, keeping
the user's preferences, their installed addons and their preference packs. Last
application in the "one mechanism for the desktop apps" backlog item, after
OrcaSlicer and PrusaSlicer.

## Context discovered

**Versions and cost:**

| Source | Version |
| --- | --- |
| Flatpak (`org.freecad.FreeCAD`) | 1.1.3 |
| Main nixpkgs pin (`3ed67ec0`) | **1.1.3** |

Exact parity, so no dedicated pin is needed — the same conclusion as PrusaSlicer
and the same reason: the `nixpkgs-orca` pin is the exception, not the pattern.
It is in the binary cache: 183 paths, 920 MiB download, **3.5 GiB unpacked**, which
is the largest of the three migrations and the number to weigh.

**FreeCAD 1.1 keeps its user state under a versioned directory.** The live
configuration is `config/FreeCAD/v1-1/user.cfg`, while `config/FreeCAD/user.cfg` is
the older layout. Data follows the same shape:
`data/FreeCAD/v1-1/{Mod,Macro,Material,SavedPreferencePacks}`. Anything migrating
these files has to carry the versioned subtree, not just the top level.

**Two configurations already exist, which is the awkward part:**

| Location | Date | Size |
| --- | --- | --- |
| Flatpak, `config/FreeCAD/v1-1/user.cfg` | same day, live | 55 KB |
| Flatpak, `config/FreeCAD/user.cfg` | months older | 54 KB |
| Native, `~/.config/FreeCAD/user.cfg` | ~11 months older | 42 KB |

The native one was left by an earlier native run — most plausibly
`nix shell nixpkgs#freecad`, since there is no trace of FreeCAD in the nix profile
and none in this repository. It uses the older layout. Migrating therefore means
the Flatpak's live configuration **supersedes** it, and the old one is preserved in
the backup rather than merged, so nothing is silently combined.

**User addons exist only inside the Flatpak**: `data/FreeCAD/v1-1/Mod/` holds
`A2plus` and `Manipulator`, about 18 MB of third-party Python workbenches. They are
migrated with the rest. They are not published anywhere by this change, so no
redistribution question arises; only the licence of the upstream projects is
relevant to them, and they are not vendored into the repository.

**Qt theming will differ, and is deliberately not addressed here.** FreeCAD is a
Qt application, so the global `flake.homeModules.gtk` theme — which fixed
OrcaSlicer and PrusaSlicer — does nothing for it. The Flatpak inherits Breeze from
its KDE runtime. Natively:

- `QT_QPA_PLATFORMTHEME` is **unset** in the session, so Qt ignores `qt6ct` and
  falls back to Fusion, which is light.
- The user does have `~/.config/qt6ct/qt6ct.conf` with a dark custom palette and
  Flat-Remix icons, and `/usr/bin/qt6ct` exists — but as a **Debian** package, and
  its platform-theme plugin would have to be ABI-compatible with the nix Qt build.
  Mixing the two is exactly the kind of fragility worth avoiding.

So the native build will probably open light. Fixing that belongs in a separate
change, ideally with a per-application wrapper as OrcaSlicer used, because a
session-wide variable on gear5th is the mechanism that has already taken the
session down twice.

## Decisions

- **Main nixpkgs pin**, for the exact-parity reason above.
- **Migrate the Flatpak's configuration wholesale**, carrying the `v1-1` subtree,
  and set the earlier native configuration aside rather than merging it.
- **Back up both sides first**, with verified checksums, before anything is moved.
- **Keep the Flatpak** until the native build is validated in use, as with the
  other two migrations.
- **Qt theming out of scope**, recorded as a follow-up with the reasoning.

## Tasks

1. Back up both configurations to a dated directory outside the repository.
2. Set the earlier native configuration aside and place the Flatpak's in
   `~/.config/FreeCAD` and `~/.local/share/FreeCAD`.
3. Add `modules/features/freecad.nix` and register it on gear5th.
4. Build, then verify the application starts and reads the migrated preferences
   and addons.
5. Commit and ship through the issue-first PR flow.

## Risks

- **3.5 GiB unpacked** is the largest footprint of the three, and the thing to
  weigh against keeping the Flatpak.
- The addons are third-party Python workbenches written for FreeCAD 1.x; they
  should load, but a version mismatch would only show at runtime, so the check is
  to load them rather than to assume.
- Superseding the earlier native configuration is a real loss of state if the
  backup is not verified first, hence the ordering above.

## Verification evidence

Backup, taken before anything moved:

- `~/backups/freecad/<timestamp>/` holds the Flatpak's `config` and `data` as
  **copies**, and the earlier native `config` and `data` as **moves**, so the older
  state exists in exactly one place rather than being duplicated and deleted.
  750 files hashed, integrity verified, plus a `MANIFEST.md` with restore commands
  for both directions.

Migration:

- 6 files into `~/.config/FreeCAD` and 739 into `~/.local/share/FreeCAD`, carrying
  the versioned `v1-1/` subtree.
- The addons arrived: `A2plus` and `Manipulator` are present under
  `v1-1/Mod/`.

Package and application:

- `nix build .#homeConfigurations.gear5th.activationPackage` succeeds; the package
  provides `freecad`, `FreeCAD`, `freecadcmd`, `FreeCADCmd` and a thumbnailer.
- `freecadcmd --version` reports **1.1.3**, matching the Flatpak.
- Headless, the application reports the native paths:
  `appdata = ~/.local/share/FreeCAD/v1-1/` and `config = ~/.config/FreeCAD/v1-1/`,
  and the mtime of the migrated `v1-1/user.cfg` advanced when it ran, so the file
  was genuinely read and rewritten rather than merely present.

### The finding worth carrying forward

The first headless run reported a **macro directory still inside the Flatpak**:

```
macro: /home/<user>/.var/app/org.freecad.FreeCAD/data/FreeCAD/v1-1/Macro
```

The migrated configuration stores an absolute `MacroPath`, written while the
application ran sandboxed. Five files carried it: both `user.cfg` layouts and three
preference-pack backups. Repointing the sandbox prefix to the native equivalent
fixed it, confirmed by the same check now reporting
`macro: ~/.local/share/FreeCAD/v1-1/Macro`.

Left alone, the application would have kept reading the Flatpak's macro directory
— which breaks the moment the Flatpak is removed, and which would have looked like
it worked until then. **A wholesale configuration migration carries absolute paths,
and the ones to hunt are the sandbox prefix, not every absolute path.**

That distinction matters, because the same scan surfaced a dozen `~/LDATA/...`
paths — recent files, working directories, last-used folders. Those are the user's
own documents, valid natively exactly as they were under the Flatpak, and they
needed no change. Flagging every absolute path as "needs repointing" was wrong; only
the sandbox-prefixed ones were.

One residue is harmless and deliberately not chased: 106 `.pyc` files under the
addons still embed the sandbox path as their compiled source filename. Bytecode
caches are regenerated when the source changes, and a mismatched Python version
invalidates them anyway.

## Follow-ups

- Qt theming for FreeCAD: a per-application wrapper rather than a session-wide
  variable, once the application is confirmed working.
- Remove the FreeCAD Flatpak once the native build is trusted; that also frees
  `org.kde.Platform//6.10`, the last runtime it keeps on gear5th.
