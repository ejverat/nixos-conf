# Feature: niri keybinding completion

## Goal

Map the niri actions that the wrapper config leaves unbound, keeping the
existing muscle memory intact, and fix two real defects found while auditing:
audio keys that do not work on the lock screen, and wheel binds with no
cooldown.

## Decisions

- **The source of truth is the store config, not `~/.config/niri/config.kdl`.**
  The wrapper exports `NIRI_CONFIG` to the generated `niri-config.kdl`; the
  643-line file under `~/.config/niri` is a leftover from an older manual
  install and is ignored by the compositor. Nothing in this repo manages it, so
  this feature does not touch it.
- **`Mod+V` follows the niri default** (`toggle-window-floating`). The
  commented `amixer` push-to-talk line is deleted instead of revived: the
  floating toggle is the upstream contract and `Mod+Shift+F` keeps working as
  the previous alias.
- **Bind properties use the wrapper's function form.** `"Key".action = ...`
  cannot express `allow-when-locked`, `cooldown-ms`, `repeat` or
  `allow-inhibiting`; those binds use
  `"Key" = _: { props.<x> = ...; content.<action> = _: { }; }`. The wrapper runs
  `niri validate` in the derivation's `installPhase`, so a wrong key or
  property fails the build.
- **Audio stays on `wpctl`, not on the noctalia IPC.** The current binds cap the
  sink at `-l 1.4`; `noctalia-shell ipc call volume` would drop that cap and
  change volume behavior. Only the lock-screen fix is applied.
- **Media transport keys use the noctalia IPC**, because noctalia's
  `MediaService` is pure MPRIS over D-Bus while `playerctl` is only present on
  gear5th as a Debian package.
- **Brightness keys use the noctalia IPC** for the on-screen display, which
  makes `brightnessctl` a real dependency: noctalia's `BrightnessService`
  shells out to it for internal panels. Chopper has no `brightnessctl` today, so
  the package is added to both host layers next to the bind that needs it.
- **Every spawn bind carries a `hotkey-overlay-title`.** niri's overlay prints
  the raw command of a spawn bind, and every command in this config is an
  absolute store path. Custom-titled binds are listed before the non-customized
  spawn binds, so the titles replace the paths instead of adding to them. The
  `spawnSh`/`spawnShLocked` helpers keep the call sites one line each.
- **Monitor binds avoid `Mod+Shift+HLJK` and `Mod+Alt+L`**: the first is already
  `move-window`/`move-column`, the second is the same physical combo as the
  existing `Super+Alt+L` lock (`Mod` is `Super` on a TTY).

## Hotkey overlay length (investigated after the first four commits)

niri's overlay has no column, width, height, font or scroll setting. From
`src/ui/hotkey_overlay.rs` (niri 26.04):

- `// FIXME: if it doesn't fit, try splitting in two columns or something.` is an
  open upstream FIXME, with the output-size clamp commented out next to it.
- The constants are `FONT = "sans 14px"`, `PADDING = 8`, `LINE_INTERVAL = 2`,
  `TITLE = "Important Hotkeys"`, so the rendered height is
  `20n + 2(n-1) + 20 + 24 = 22n + 42` physical pixels at scale 1.
- The dialog is centred with `(output_size - size) / 2` and clamped at `0`, so
  when the content is taller than the output the *last* rows are the ones cut.
- `hide-not-bound` removes nothing here: all 19 hardcoded actions are bound.
- Row content = 19 hardcoded actions + every bind carrying a non-null
  `hotkey-overlay-title`. `hotkey-overlay-title=null` removes a row.

Row budget per output (kanshi sets both to scale 1.0):

| Output | Logical height | Rows that fit |
| --- | --- | --- |
| `eDP-1` 1366x768 | 768 | 33 |
| `HDMI-A-1` 1920x1080 | 1080 | 47 |

The config had 46 rows (19 + 27 titles), which fits the external monitor and
loses 13 rows on the laptop panel. Two rounds of `hotkey-overlay-title=null`
land it on the 33-row budget:

1. The 10 `XF86*` media and brightness keys, which are printed on the keyboard.
2. The bluetooth, network and calendar panels, which the control center on
   `Mod+A` already exposes.

The final overlay is 19 hardcoded rows + 14 titles = 33 rows = 768 px, which
fills the laptop panel exactly and leaves room to spare on the external one.
The margin is zero on `eDP-1`, so a host whose `sans` resolves to a taller font
would cut the last row again; the next row to sacrifice is `Mod+Shift+M` (media
player panel).

## Tasks

1. Branch `feat/niri-keybindings` and this document.
2. Commit 1: shell, session and capture binds (noctalia panels, screenshot UI,
   `quit`, `power-off-monitors`, shortcut inhibitor, orca).
3. Commit 2: layout, sizing and floating binds (preset widths, tabbed display,
   consume/expel, `maximize-window-to-edges`, `Mod+V`).
4. Commit 3: workspace, monitor and wheel binds (`move-to-workspace` keys,
   monitor focus/move, `cooldown-ms` on the wheel binds).
5. Commit 4: media keys, brightness and `allow-when-locked` on audio.
6. Commit 5: hotkey overlay titles for every spawn bind, so the startup
   "Important Hotkeys" dialog stops printing absolute store paths.
7. Verification: `nix build .#myNiri` (runs `niri validate`), duplicate-bind
   check over the generated KDL, and a final `git diff main`.

## Verification evidence

- [x] `nix build .#myNiri` exits 0 after every commit; the wrapper's
  `installPhase` runs `niri validate`, so the config format and every new bind
  property were validated at build time.
- [x] `nix run .#myNiri -- validate -c <store>/niri-config.kdl` prints
  `config is valid` (exit 0).
- [x] No duplicate bind keys: 128 binds, 0 duplicates.
- [x] Nothing removed: `keys removed vs old: none`; 70 keys added.
- [x] Action coverage grew from 21 to 64 of the 142 actions `niri msg action`
  reports for 26.04.
- [x] Host layers build: `.#nixosConfigurations.chopper.config.system.build.toplevel`
  (exit 0, 36m) and `.#homeConfigurations.gear5th.activationPackage`
  (exit 0).
- [x] `brightnessctl` present in `nixosConfigurations.chopper.config.environment.systemPackages`
  and in `homeConfigurations.gear5th.config.home.packages`.
- [x] Hotkey overlay: 27 spawn binds and 27 `hotkey-overlay-title` properties in
  the generated config, so no bind can show a store path.
- [x] `niri validate` prints `config is valid` after the overlay change.
- [x] Overlay row budget verified against the niri source constants: 19
  hardcoded + 14 titles = 33 rows = 768 px, matching the `eDP-1` logical height;
  13 binds carry `hotkey-overlay-title=null` (10 `XF86*` + 3 panels).

Not verified on the running session: the live compositor still runs the config
from the previously activated profile. The binds take effect on the next
`home-manager switch` / `nixos-rebuild switch` (the wrapper hot-reloads through
`niri.service`'s `ExecReload`).

## Commit identities

- [x] `feat(niri): bind shell, session and capture actions` (515a08f)
- [x] `feat(niri): complete the layout and floating binds` (19a9b04)
- [x] `feat(niri): add workspace, monitor and wheel navigation binds` (c0875d7)
- [x] `feat(niri): wire media and brightness keys` (4e736d7)
- [x] `feat(niri): title every spawn bind in the hotkey overlay`
- [x] `feat(niri): drop the media keys from the hotkey overlay`
- [x] `feat(niri): fit the hotkey overlay on the laptop panel`
