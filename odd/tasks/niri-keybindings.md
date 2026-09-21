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
- **Monitor binds avoid `Mod+Shift+HLJK` and `Mod+Alt+L`**: the first is already
  `move-window`/`move-column`, the second is the same physical combo as the
  existing `Super+Alt+L` lock (`Mod` is `Super` on a TTY).

## Tasks

1. Branch `feat/niri-keybindings` and this document.
2. Commit 1: shell, session and capture binds (noctalia panels, screenshot UI,
   `quit`, `power-off-monitors`, shortcut inhibitor, orca).
3. Commit 2: layout, sizing and floating binds (preset widths, tabbed display,
   consume/expel, `maximize-window-to-edges`, `Mod+V`).
4. Commit 3: workspace, monitor and wheel binds (`move-to-workspace` keys,
   monitor focus/move, `cooldown-ms` on the wheel binds).
5. Commit 4: media keys, brightness and `allow-when-locked` on audio.
6. Verification: `nix build .#myNiri` (runs `niri validate`), duplicate-bind
   check over the generated KDL, and a final `git diff main`.

## Verification evidence

- [ ] `nix build .#myNiri` exits 0 after each commit (validates the config).
- [ ] No duplicate bind keys in the generated `niri-config.kdl`.
- [ ] Every new key is absent from the pre-change bind set.

## Commit identities

- [ ] `feat(niri): bind shell, session and capture actions`
- [ ] `feat(niri): complete the layout and floating binds`
- [ ] `feat(niri): add workspace, monitor and wheel navigation binds`
- [ ] `feat(niri): wire media and brightness keys`
