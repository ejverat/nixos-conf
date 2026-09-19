# Feature: native OrcaSlicer 2.4.2 for gear5th (drop Flatpak)

## Goal

Run OrcaSlicer 2.4.2 on **gear5th** (Debian, home-manager standalone) as a
Nix-managed package instead of a Flatpak, without losing the user's print
profiles. Additionally remove the abandoned legacy Flatpak install.

## Context discovered

Two Flatpaks coexist today on gear5th (both `system` installation):

| App ID | Version | Origin | Notes |
| --- | --- | --- | --- |
| `com.orcaslicer.OrcaSlicer` | 2.4.2 | flathub | current, official ID |
| `io.github.softfever.OrcaSlicer` | 2.0.0-951fc8e | `orcaslicer-origin` | sideloaded bundle, legacy ID |

The legacy install is not a real remote: `orcaslicer-origin` has an empty
`url`, `xa.noenumerate=true` and `gpg-verify=false`, i.e. a leftover from a
local `.flatpak` bundle install (bundle filename says `V2.3.1`, hence the
"2.3.1" label). It is not listed by `flatpak remotes` for that reason.

Packaging facts for the native path:

- `pkgs.orca-slicer` exists in nixpkgs, built **from source**
  (`fetchFromGitHub` of tag `v2.4.2`, CMake + `clangStdenv`), not an AppImage.
- Main nixpkgs pin `3e41b24` (2026-06-16) ships **2.3.2**.
- `nixos-unstable` currently ships **2.4.2**, and the output is in the binary
  cache (349 paths, ~662 MiB download) so nothing gets compiled.

### Profile paths (verified in upstream source, `src/slic3r/GUI/GUI_App.cpp`)

Native Linux config dir is `${XDG_CONFIG_HOME:-$HOME/.config}/<AppName>`, and
`AppName` is `OrcaSlicer`. So:

- Flatpak: `~/.var/app/com.orcaslicer.OrcaSlicer/config/OrcaSlicer`
- Native: `~/.config/OrcaSlicer`

The upstream auto-migration helper `migrate_flatpak_legacy_datadir()` only runs
when `/.flatpak-info` exists, i.e. **only for a Flatpak build**. The native
build will NOT migrate anything: the copy must be done manually.

## Decisions

- **Option B (dedicated nixpkgs pin), as requested.** A new `nixpkgs-orca`
  input (nixos-unstable) is added next to the existing `nixpkgs-pi` /
  `nixpkgs-pnpm` pins, so OrcaSlicer 2.4.2 is available today without bumping
  the main nixpkgs pin. Accepted tradeoff: the pin brings its own dependency
  closure (duplicated `webkitgtk`, `wxwidgets`, ...), isolated from the main
  pin. Justified by the 2.4.2-vs-2.3.2 gap.
- **Feature lives in the shared layer.** gear5th is Debian, so the deliverable
  is `flake.homeModules.orcaslicer`. A matching `flake.nixosModules.orcaslicer`
  is exported so chopper can opt in later; chopper registration is **not** done
  here (different machine, not requested).
- **No NVIDIA workaround.** `withNvidiaGLWorkaround` is for the proprietary
  driver; gear5th has an AMD `Radeon RX 580 (Polaris 20 XL)`.
- **Profiles stay runtime state.** Presets are edited in the GUI, so they live
  in `~/.config/OrcaSlicer` (like `~/.pi`), not in home-manager `home.file`.
  Nix manages the *binary*; the user keeps owning the presets.
- **Keep the 2.4.2 Flatpak** for now (rollback path). Only the legacy install
  is removed, as asked. The duplicate launcher entry is a known, temporary
  consequence.

## Tasks

1. Back up the 2.4.2 Flatpak config + data, and the legacy config, to
   `~/backups/orcaslicer/<timestamp>/` (outside the repo).
2. Remove the legacy Flatpak `io.github.softfever.OrcaSlicer` and the
   `orcaslicer-origin` remote.
3. Add the `nixpkgs-orca` input to `flake.nix` and update `flake.lock`.
4. Add `modules/features/orcaslicer.nix` (`homeModules` + `nixosModules`).
5. Register `self.homeModules.orcaslicer` in `modules/hosts/gear5th/default.nix`.
6. Build/activate the gear5th home configuration; eval chopper (unchanged).
7. Migrate profiles into `~/.config/OrcaSlicer`.
8. Verify the native binary runs and the presets are visible.
9. Work-unit commit.

## Risks and follow-ups

- The legacy config holds 2 process presets absent from 2.4.2
  (`0.20mm Standard - OVERTUNE Generic`, `.info` + `.json`). They are kept in
  the backup; importing them into the native instance is a user decision.
- `flatpak uninstall` without `--delete-data` keeps `~/.var/app/<id>`, so the
  legacy data survives removal regardless of the backup.
- Follow-up: drop the 2.4.2 Flatpak once the native app is validated.
- Follow-up: `home-manager switch` must be run by the user (or with approval)
  to activate the change.

## Verification evidence

Backup (task 1):

- `~/backups/orcaslicer/20260918-235724/` holds 2.4.2 `config` + `data` and the
  legacy `config` (49 MB, 2358 files before the manifest was excluded).
- `SHA256SUMS` covers 2357 files and `sha256sum -c` reports integrity OK.
- `diff -r` against both live sources reports **idéntico**.
- Backup includes `MANIFEST.md` with restore commands.

Legacy removal (task 2):

- `flatpak uninstall --system --noninteractive io.github.softfever.OrcaSlicer`
  removed the app **and** the now-orphaned runtime `org.gnome.Platform` 47.
- The fake remote disappeared with the app: `flatpak remotes` now lists only
  `flathub`, and `/var/lib/flatpak/repo/config` contains only `[remote flathub]`
  (a later `remote-delete orcaslicer-origin` correctly failed with "not found").
- `~/.var/app/io.github.softfever.OrcaSlicer` (15 MB) survives, as intended.

Pin and build (tasks 3-6):

- `nixpkgs-orca` locked at `e554fab72f81915600f3f449b786fd9af40439a5`
  (2026-09-17); `orca-slicer.version` from that pin is **2.4.2**.
- `nix build --dry-run` reports the identical cached output
  `/nix/store/pgpyhy1g59fc5sxc8lxjpzvjfyvx0r48-orca-slicer-2.4.2`, i.e. fetched,
  never compiled.
- `nix build .#homeConfigurations.gear5th.activationPackage` succeeds.
- `nix eval .#nixosConfigurations.chopper.config.system.build.toplevel.drvPath`
  still succeeds, so exporting `nixosModules.orcaslicer` broke nothing on the
  other host.
- Diffing the previous and new `home-path` trees shows the only additions are
  `include`, `bin/orca-slicer`, `bin/.orca-slicer-wrapped` and
  `share/applications/com.orcaslicer.OrcaSlicer.desktop`. Activation therefore
  changed nothing else.

Profile migration (task 7):

- `~/.config/OrcaSlicer` created from the Flatpak data dir; `user/` (57 files),
  `printers/` (16), `system/` (735), `OrcaSlicer.conf` and `user_backup-v2.4.2`
  all diff-identical to the source.
- Excluded on purpose: 23 stale `log/*.log.0` files and the single-instance
  `cache/*.lock`, so 893 source files migrated as 869 intentional files.

Runtime (task 8):

- `ldd` on the real binary (`bin/.orca-slicer-wrapped`, 68 MB) resolves all 261
  libraries with **0** missing. `bin/orca-slicer` is the compiled
  `wrapGAppsHook3` wrapper injecting `WEBKIT_DISABLE_COMPOSITING_MODE=1`,
  `LD_LIBRARY_PATH`, `GIO_EXTRA_MODULES` and `XDG_DATA_DIRS`.
- Launched from the store against a live Wayland session: it starts in
  `gui mode, Current OrcaSlicer Version 2.4.2` and its log references the user
  printer `Kingroon KP3S PRO S1`, proving the migrated presets were read.
- Log noise is benign for a non-official build: `get_version not supported`
  (no updater), `calc_exclude_triangles`, missing `Metadata/plate_1.png` in
  3mf archives, and `_parse_printer_type Unsupported printer type` for the
  user's own printer.
- After activation: `orca-slicer` resolves to
  `~/.nix-profile/bin/orca-slicer` -> the 2.4.2 store path, and the presets are
  still 57 + 16. `home-manager generations` shows id 16 (current) over id 15.

## Follow-ups (not done, need a user decision)

1. **Launcher visibility is broken and pre-existing.** `~/.nix-profile/share`
   is not in `XDG_DATA_DIRS` (`/home/ejverat/.local/share/flatpak/exports/share`
   is first) and `etc/profile.d/hm-session-vars.sh` is not sourced anywhere.
   The Nix `.desktop` for **wezterm is already invisible for the same reason**,
   so this predates this change. The canonical fix is
   `targets.genericLinux.enable = true` in gear5th's `hostModule`, which sets
   session-wide `XDG_*` variables and therefore needs its own decision.
2. **Duplicate launcher id.** The Flatpak and the Nix package both export
   `com.orcaslicer.OrcaSlicer.desktop` (same `Name=OrcaSlicer`). Keeping the
   2.4.2 Flatpak collides with the native entry once (1) is solved.
3. **Drop the 2.4.2 Flatpak** as the rollback path, now that the native build
   is verified: `flatpak uninstall --system com.orcaslicer.OrcaSlicer`.
4. **Two legacy process presets** exist only in the legacy backup
   (`0.20mm Standard - OVERTUNE Generic`, `.info` + `.json`); importing them
   is optional.
5. **Work-unit commit**
   `cbb015e0b4bee2f344d5fb8ac969f86731e32b59` on
   `feat/orcaslicer-native-gear5th` (branch cut from `main` at `f6c661b`).
   Deliberately not committed to `main`: this repo's history is PR-based.

## GTK theme (reported after #18 merged)

The native app opened in a light theme while the Flatpak opened dark. Cause:
gear5th's `~/.config/gtk-3.0/settings.ini` names
`Nordic-bluish-accent-standard-buttons-v40`, but `~/.themes` does not exist (the
files only survive under `~/.dotfiles.bak/home/.themes`, which the `dotfiles`
module does not materialize), so GTK cannot resolve the theme and falls back to
Adwaita light. OrcaSlicer is effectively the only GTK3 app on gear5th, which is
why this went unnoticed. The Flatpak was immune by accident: its sandbox
redirects `XDG_CONFIG_HOME` to `~/.var/app/<id>/config`, whose `gtk-3.0/` is
empty, so it used the host gsettings value (`Flat-Remix-GTK-Blue-Dark`,
`prefer-dark`) through its `org.gtk.Gtk3theme.*` extension instead.

Decision: fix it **for OrcaSlicer only**, not globally. `GTK_THEME` takes
precedence over `settings.ini` and touches nothing else, which also avoids
landing on `~/.config/gtk-3.0/settings.ini` — a real file that a home-manager
`gtk` module would have to take over, the same class of activation collision
noted for the standalone host. Theme chosen: `Adwaita-dark`, already present in
`/usr/share/themes`, so no new dependency.

Implementation notes worth keeping:

- The package's `bin/orca-slicer` is a compiled `wrapGAppsHook3` wrapper whose
  real binary is `bin/.orca-slicer-wrapped`. `wrapProgram` would rename the
  target to `.<name>-wrapped` and overwrite that 68 MB binary, so the module
  builds a fresh `symlinkJoin` wrapper over the absolute store path instead.
- Verified safe because the gapps wrapper execs `.orca-slicer-wrapped` by
  absolute path and the real binary resolves `share/OrcaSlicer` by absolute
  path. The produced wrapper has **zero** self-references, so there is no
  recursion, and `--info` on a real STL still succeeds through it.
- `flat-remix-gtk` is **gone from nixpkgs** (it depended on
  `gtk-engine-murrine`, dropped with GTK2), so the Flatpak's exact look is not
  reproducible from nixpkgs. `pkgs.nordic` does exist and provides
  `Nordic-bluish-accent-standard-buttons` (no `-v40` suffix) if that look is
  preferred later.
- Work-unit commit:
  `f31d2cba129791bfb3d6c675969d8e7df21e7b05` on
  `feat/orcaslicer-dark-theme` (branch cut from `main` at `5e1dec0`).
