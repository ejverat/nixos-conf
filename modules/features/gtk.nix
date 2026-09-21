{ ... }: {
  # Global GTK configuration for gear5th.
  #
  # This host never had a working GTK setup. `~/.config/gtk-3.0/settings.ini`
  # was a hand-written file naming `Nordic-bluish-accent-standard-buttons-v40`,
  # but `~/.themes` does not exist: those files only survive under
  # `~/.dotfiles.bak`, which the `dotfiles` module does not materialize, and
  # nothing installs the theme either. GTK therefore could not resolve the
  # theme and silently fell back to Adwaita light. It went unnoticed for a long
  # time because OrcaSlicer was effectively the only GTK 3 application on this
  # host, and it only became visible once the app moved from Flatpak (whose
  # sandbox redirects XDG_CONFIG_HOME to an empty gtk-3.0/ and used the host
  # gsettings value instead) to a native build that reads settings.ini.
  #
  # `pkgs.nordic` ships the same Nordic variants, but without the `-v40`
  # suffix the upstream tarball uses, hence the name below. The Flatpak's
  # `Flat-Remix-GTK-Blue-Dark` is not an option: `flat-remix-gtk` was removed
  # from nixpkgs because it depended on `gtk-engine-murrine`, dropped with
  # GTK 2. `flat-remix-gnome` and `flat-remix-icon-theme` do still exist.
  #
  # Two things must hold for this module to have any effect, and neither is
  # part of it:
  #
  #   1. `~/.nix-profile/share` must be in XDG_DATA_DIRS, because that is where
  #      GTK looks for `themes/<name>`. On NixOS the system profile provides
  #      this; on Debian it comes from `targets.genericLinux.enable` in gear5th's
  #      hostModule. Naming a theme that cannot be found is exactly the bug this
  #      module is fixing, so the two changes belong together.
  #   2. The login shell must source home-manager's `hm-session-vars.sh`, which
  #      is what carries XDG_DATA_DIRS into the session. `targets.genericLinux`
  #      wires that into bash only, so the portable zsh wrapper sources it too.
  #
  # A session restart is required after the first activation of either change.
  flake.homeModules.gtk = { pkgs, ... }: {
    gtk = {
      enable = true;
      theme = {
        name = "Nordic-bluish-accent-standard-buttons";
        package = pkgs.nordic;
      };
      iconTheme = {
        name = "Adwaita";
        package = pkgs.adwaita-icon-theme;
      };
      cursorTheme = {
        name = "Adwaita";
        package = pkgs.adwaita-icon-theme;
      };
      font = {
        name = "Sans";
        size = 10;
      };
      colorScheme = "dark";

      # The hand-written settings.ini carried preferences the module does not
      # model. Keep them verbatim so taking the file over loses nothing.
      gtk3.extraConfig = {
        gtk-application-prefer-dark-theme = 1;
        gtk-toolbar-style = "GTK_TOOLBAR_BOTH_HORIZ";
        gtk-toolbar-icon-size = "GTK_ICON_SIZE_LARGE_TOOLBAR";
        gtk-button-images = 0;
        gtk-menu-images = 0;
        gtk-enable-event-sounds = 1;
        gtk-enable-input-feedback-sounds = 1;
        gtk-xft-antialias = 1;
        gtk-xft-hinting = 1;
        gtk-xft-hintstyle = "hintmedium";
      };
    };

    # `~/.config/gtk-3.0/settings.ini` is a real hand-written file, so the
    # managed file needs permission to replace it. Its content is preserved by
    # the options above; without `force` the activation would refuse the
    # collision instead (home-manager standalone has no `backupFileExtension`).
    xdg.configFile."gtk-3.0/settings.ini".force = true;
  };
}
