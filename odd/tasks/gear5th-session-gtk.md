# Feature: wire up the session environment on gear5th (GTK theme + XDG_DATA_DIRS)

## Goal

Make gear5th's GTK applications resolve a real theme, and make Nix `.desktop`
entries visible to the desktop launcher. Both are symptoms of the same hole:
this Debian host never had the XDG plumbing a NixOS system profile provides.

## Context discovered

- `~/.config/gtk-3.0/settings.ini` was a hand-written file naming
  `Nordic-bluish-accent-standard-buttons-v40`, but `~/.themes` does not exist:
  those files only survive under `~/.dotfiles.bak/home/.themes`, which the
  `dotfiles` module does not materialize, and nothing installs the theme either.
  GTK therefore could not resolve the theme and silently fell back to Adwaita
  light. OrcaSlicer was effectively the only GTK 3 application on this host, so
  it went unnoticed until the app moved off the Flatpak — whose sandbox
  redirects `XDG_CONFIG_HOME` to an empty `gtk-3.0/`, making it read the host
  gsettings value instead and look dark by accident.
- `~/.nix-profile/share` was missing from `XDG_DATA_DIRS`, and
  `hm-session-vars.sh` was never sourced. That broke **two** things at once:
  GTK could not find `themes/<name>` even when `settings.ini` named one, and
  desktop launchers could not see any Nix `.desktop` entry (wezterm included).
- `targets.genericLinux` wires `hm-session-vars.sh` into **bash only**, so a zsh
  login shell — this host's shell, and the one that starts the niri session —
  would still never see the variables.

The two fixes are therefore **coupled, not independent**: naming a theme GTK
cannot find is the very bug being fixed, so the theme change is inert without
the `XDG_DATA_DIRS` change, and the `XDG_DATA_DIRS` change is inert without the
zshenv sourcing.

## Decisions

- **Fix the cause, not the symptom.** The per-app `GTK_THEME` wrapper added in
  #20 is removed: it was a workaround for the broken global config, and keeping
  it would leave OrcaSlicer as the one GTK application on the machine pinned to
  a different theme, silently overriding any later theme change.
- **Theme: `pkgs.nordic`**, the user's originally intended family. nixpkgs ships
  the same variants **without** the upstream `-v40` suffix, hence
  `Nordic-bluish-accent-standard-buttons`. `flat-remix-gtk` is not an option: it
  was removed from nixpkgs because it depended on `gtk-engine-murrine`, dropped
  with GTK 2. (`flat-remix-gnome` and `flat-remix-icon-theme` do still exist.)
- **Use home-manager's `gtk` module** rather than a hand-written file, so the
  theme is reproducible and the package is installed by the same expression.
- **Preserve the existing preferences.** The hand-written `settings.ini` carried
  toolbar, button-image, sound and xft keys the module does not model; they are
  carried over verbatim through `gtk3.extraConfig`, so taking the file over
  loses nothing.
- **`force = true` on the settings file.** It exists as a real file on a managed
  path; without `force` the activation refuses the collision instead
  (home-manager standalone has no `backupFileExtension`). `bookmarks` is only
  written when non-empty, so the user's bookmarks file is untouched.

## Tasks

1. Add `modules/features/gtk.nix` (`flake.homeModules.gtk`).
2. Enable `targets.genericLinux` in gear5th's `hostModule`.
3. Source `hm-session-vars.sh` from the portable zsh `zshenv`.
4. Remove the per-app `GTK_THEME` wrapper from `modules/features/orcaslicer.nix`.
5. Build, verify the generated `settings.ini` and `XDG_DATA_DIRS`, confirm
   chopper still evaluates.
6. Activate, then commit and ship through the issue-first PR flow.
   Work-unit commit `01c437b1bec9a27e5c4957ab9e967208c5bdb1bf` on
   `feat/gear5th-session-gtk-theme`, cut from `main` at `b7e2452`.

## Risks

- `targets.genericLinux` changes session-wide variables (`XDG_DATA_DIRS`,
  `XCURSOR_PATH`, `TERMINFO_DIRS`, `NIX_PATH`) and enables its GPU submodule,
  which adds a `non-nixos-gpu-setup` helper to the profile. It requires a
  **session restart** to take effect, because the running niri session inherited
  its environment before the change.
- Until the session is restarted, `settings.ini` names a theme GTK may not be
  able to find in the current environment. `gtk-application-prefer-dark-theme=1`
  should keep the result dark via the fallback, but the intended Nordic look
  only applies after the restart.

## Verification evidence

- `nix build .#homeConfigurations.gear5th.activationPackage` succeeds.
- Generated `~/.config/gtk-3.0/settings.ini` carries
  `gtk-theme-name=Nordic-bluish-accent-standard-buttons` and
  `gtk-application-prefer-dark-theme=1`, and preserves the toolbar, button-image,
  sound and xft keys the hand-written file had.
- `homeConfigurations.gear5th.config.home.sessionVariables.XDG_DATA_DIRS`
  resolves to a value starting with the nix profiles, including
  `$HOME/.nix-profile/share`, which is where GTK finds `themes/<name>`.
- The profile carries all eight `Nordic*` theme directories under
  `share/themes/`.
- `orca-slicer` resolves straight to the pinned package with **0** references to
  `GTK_THEME`, so the per-app wrapper is gone.
- `nix eval .#nixosConfigurations.chopper.config.system.build.toplevel.drvPath`
  still succeeds.
- The only profile-wide additions from `targets.genericLinux` are a `resources`
  directory and the `non-nixos-gpu-setup` helper from its GPU submodule.
- Live confirmation after the session restart: niri's environment carries
  `XDG_DATA_DIRS` including `$HOME/.nix-profile/share`, so the launcher and GTK
  both resolve Nix content.

### Idempotency guard (found by inspecting the live environment)

The first version of the `zshenv` sourcing was not idempotent, and the live
session showed `XDG_DATA_DIRS` containing `~/.nix-profile/share` **three**
times. `zshenv` runs for every zsh invocation and `hm-session-vars.sh` appends
rather than replaces, so nested shells grew both `XDG_DATA_DIRS` and
`TERMINFO_DIRS` without bound. A `__HM_SESSION_VARS_SOURCED` guard fixes it.

Measured with the built wrapper through one, two and three levels of nested
zsh: **1 / 1 / 1** occurrences after the guard, against 1 / 2 / 3 before it.

### Incident: the first activation tore down the graphical session

The first `home-manager switch` with this change stopped `niri.service`, closed
the graphical session, killed the tmux panes and dropped the user to tty1; a
reboot was needed to recover. The journal shows the mechanism:

```
20:44:40 systemd[2409]: Stopping niri.service - A scrollable-tiling Wayland compositor...
20:44:40 niri[10913]: quitting due to receiving signal SIGTERM
20:44:40 systemd[2409]: Stopped tmux-spawn-...scope - tmux child pane 15170 ...
```

Cause: `targets.genericLinux` adds `systemd.user.sessionVariables`, which
altered `~/.config/environment.d/10-home-manager.conf`. Home Manager applies
systemd changes through `sd-switch`, and `niri.service` is a user unit with
`BindsTo=graphical-session.target` inside `session.slice`, so stopping it takes
the whole session down. tmux died as collateral because systemd had its panes
as `tmux-spawn-*.scope` units in the same user manager.

Two lessons, both now encoded:

1. **A session restart is inherent to this fix, not incidental.** niri is a
   systemd user unit, so `XDG_DATA_DIRS` can only reach the applications it
   launches through the systemd user environment. The unavoidable part was the
   restart; the avoidable part was doing it without warning the user first.
2. **Check the unit- and environment-level diff before activating.** Comparing
   the built generation against the active one shows
   `environment.d/10-home-manager.conf` and every unit under
   `.config/systemd/user/` are now byte-identical, so a later activation has no
   environment change for `sd-switch` to apply and should not restart niri.

Operational rule adopted: never activate a switch that can disturb the session
without the user choosing the moment.

## Follow-ups

- Drop the 2.4.2 Flatpak once the native app is fully trusted.
- `result.json`: OrcaSlicer writes it into the current working directory on exit.
- Optional: vendor `Flat-Remix-GTK-Blue-Dark` (the Flatpak's exact look) from
  `~/.dotfiles.bak`, or derive it, if Nordic is not what is wanted.
- The duplicate desktop id `com.orcaslicer.OrcaSlicer.desktop` (Flatpak + Nix)
  becomes visible now that Nix `.desktop` entries actually resolve.
