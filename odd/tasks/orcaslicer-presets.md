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

- **chopper did not have OrcaSlicer installed.** `modules/hosts/chopper/configuration.nix`
  imported neither `nixosModules.orcaslicer` nor `homeModules.gtk`, so the presets
  had nowhere to land. Onboarding chopper is part of this change, and it also
  needs the NVIDIA path: chopper is NVIDIA, gear5th is AMD. *(Resolved: see
  "Chopper onboarding" below.)*
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

## Chopper onboarding

Enabling the second host needed three registrations in
`modules/hosts/chopper/configuration.nix`:

| Layer | Module | Why |
| --- | --- | --- |
| NixOS | `nixosModules.orcaslicer` | installs the app into `environment.systemPackages` |
| home | `homeModules.gtk` | without it chopper has no GTK theme at all, so OrcaSlicer would open light there exactly as it did on gear5th |
| home | `homeModules.orcaslicer-presets` | seeds the vendored presets |

Verified by evaluation first:

- `nixosConfigurations.chopper.config.system.build.toplevel.drvPath` evaluates.
- `home-manager.users.ejverat.xdg.configFile."gtk-3.0/settings.ini".text`
  contains `gtk-theme-name=Nordic-bluish-accent-standard-buttons` and
  `gtk-application-prefer-dark-theme=1`.
- `home-manager.users.ejverat.home.activation.orcaPresetSeed.data` contains the
  seed body.

### Chopper activation (hardware)

The host was then actually switched and verified, on 2026-09-20 23:45 (system
generation 119, home-manager generation `6cq3qwfzk1cdn9ljmd37ww9nafhz9d1z`):

| Check | Observed |
| --- | --- |
| app installed | `orca-slicer 2.4.2` in `/run/current-system/sw/bin` |
| seed ran | journal: `orca-presets: seeded 56 preset file(s) into /home/ejverat/.config/OrcaSlicer/user/default` |
| live vs repo | `scripts/orca-presets.sh status` reports `up to date: 56` |
| GTK theme | `~/.config/gtk-3.0/settings.ini` and the `gtk-4.0/*` files are home-manager links, and the user confirms the theme renders correctly in the app |
| `force` collision | no `*.bak` was left behind, and the managed `settings.ini` carries every key the replaced file had |
| `#38` after merging `origin/main` (`33763ce`) | chopper's `environment.systemPackages` no longer lists chromium/google-chrome/slack/teams; they resolve from `home.packages` |
| merge build | `nix build .#nixosConfigurations.chopper.config.system.build.toplevel --no-link` and `.#homeConfigurations.gear5th.activationPackage` both succeed |

### Open: partial UI rendering on the internal panel

Inside the app, some UI regions show **vertical lines** on the integrated panel
(`eDP-1`, 1366x768 @ 60.003 Hz) while the same regions are correct on the
external monitor (`HDMI-A-1`, 1920x1080 @ 60 Hz). Both outputs are scale 1;
niri 26.04, NVIDIA GTX 1650 on the proprietary driver. This is an observation,
not a diagnosis: the app is **GTK 3** (`gtk+3-3.24.52` + `wxwidgets-3.3.3.1`), so
the GTK 4 setting below cannot be its cause.

Triage order if it is worth chasing, cheapest discriminator first:

1. `GDK_BACKEND=x11 orca-slicer` — if the artifact disappears, the Wayland/GL
   client path or niri's damage tracking for that output is the suspect.
2. `GDK_GL=disable orca-slicer` — if it disappears, it is the GTK 3 GL renderer
   on the proprietary driver, which is the class `withNvidiaGLWorkaround`
   addresses (see below).
3. Move the window between outputs while running: an artifact that follows the
   window is app-side; one that stays tied to `eDP-1` is output/compositor-side
   (niri + NVIDIA with two different refresh rates).

Three things worth knowing about the second host:

1. **NixOS needs no `targets.genericLinux`.** Its defaults already put the user
   profile's share dir into `XDG_DATA_DIRS`, so `homeModules.gtk` alone is
   enough. That whole class of problem is specific to the Debian host.
2. **`homeModules.gtk` writes `settings.ini` with `force`.** On gear5th that was
   the point. On chopper it means that if a hand-written
   `~/.config/gtk-3.0/settings.ini` existed there, the managed Nordic file
   replaces it, and because `force` bypasses collision handling the NixOS
   `backupFileExtension = "bak"` would **not** leave a copy. *(Resolved at the
   first switch: no backup was needed and no key was lost — the module carries
   the old file's custom keys verbatim.)*
3. **GTK 4 theme: decision pending, recommendation `gtk.gtk4.theme = null`.**
   chopper's `home.stateVersion` is `25.11`, older than the release that changed
   the default, so home-manager keeps the legacy behaviour (GTK 4 inherits
   `gtk.theme`) and warns. What each option actually does:

   | Option | Effect |
   | --- | --- |
   | `gtk.gtk4.theme = config.gtk.theme` (legacy) | keeps writing a GTK 4 `gtk.css`/`settings.ini` that names Nordic. libadwaita applications ignore a named theme and only recolor from Adwaita, so this path mostly yields half-applied theming, and it is the deprecated behaviour. |
   | `gtk.gtk4.theme = null` (new default) | stops overriding the GTK 4 theme, so those apps use their own dark/light preference, which `gtk.colorScheme = "dark"` already sets. Silences the warning and matches gear5th (`26.11`). |

   Evidence for the recommendation: **this configuration installs no GTK 4 or
   libadwaita software at all** — no `gtk4`/`libadwaita` dependency in
   `/run/current-system/sw`, in `~/.nix-profile`, or in any `modules/*.nix`. Every
   GUI application here is GTK 3 (OrcaSlicer, GIMP), Electron/CEF (chromium,
   google-chrome, slack, teams), VCL (libreoffice), or owns its renderer
   (wezterm). So the option has no visible effect today, and taking `null`
   removes a deprecated path and the warning at no cost while `gtk.colorScheme`
   stays as the correct mechanism for the day a GTK 4 app arrives.

## NVIDIA on chopper

The `orca-slicer` package exposes `withNvidiaGLWorkaround`, which forces
Mesa/zink and disables WebKit's DMA-BUF renderer for the proprietary driver.
chopper is NVIDIA, so it may be needed there, but it was **not** enabled:
rendering on that host cannot be verified from gear5th, and forcing zink on a
working NVIDIA setup could regress it. If chopper's 3D viewport renders black or
mangles the UI, the change is one line in `orcaFor`:

```nix
(import ../lib/_pkgs.nix) inputs.nixpkgs-orca pkgs.stdenv.hostPlatform.system
```

becomes an `orca-slicer.override { withNvidiaGLWorkaround = true; }` for that
host only. Note that `nixosConf.<feature>.*` options live in the home-manager
module system (as `kanshi` shows), so they cannot govern a package that a NixOS
module installs — hence the absence of an option for this.

After the first real run on chopper this stays **off**: the reported artifact is
partial rendering on the integrated panel, not the black/mangled viewport this
workaround exists for, and the recommended triage (above) only justifies enabling
it if `GDK_GL=disable` makes the artifact disappear.

## Follow-ups

- ~~Onboard chopper~~ — done: `nixosModules.orcaslicer`, `homeModules.gtk` and
  `homeModules.orcaslicer-presets` are registered, activated and verified on the
  host (see "Chopper onboarding").
- **GTK 4 decision** — confirm `gtk.gtk4.theme = null` (recommended) or pin the
  legacy value; one line in chopper's configuration.
- **UI rendering on `eDP-1`** — triage steps recorded above; only worth chasing
  if the artifact becomes disruptive.
- The seed covers presets only; a future change could extend it to the printer
  configs if they ever become user-authored.
