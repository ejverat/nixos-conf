{ inputs, ... }: let
  # OrcaSlicer from the dedicated `nixpkgs-orca` pin: the main nixpkgs pin
  # still ships 2.3.2, and the user's print profiles come from a 2.4.2
  # Flatpak. Rationale and tradeoff: odd/tasks/orcaslicer-native.md.
  #
  # `allowUnfree` comes from the shared manual-import helper (modules/lib/_pkgs.nix),
  # the same policy the flake-level perSystem pkgs and gear5th's pkgs use.
  # orca-slicer itself is AGPL-3.0 (free); the flag is there so the closure
  # does not start failing if a dependency ever needs it.
  orcaBase = pkgs:
    ((import ../lib/_pkgs.nix) inputs.nixpkgs-orca pkgs.stdenv.hostPlatform.system)
    .orca-slicer;

  # Force the GTK theme for this app only.
  #
  # gear5th's ~/.config/gtk-3.0/settings.ini names
  # `Nordic-bluish-accent-standard-buttons-v40`, but ~/.themes does not exist
  # (those files only survive under ~/.dotfiles.bak), so GTK cannot resolve the
  # theme and falls back to Adwaita light. The Flatpak never showed this
  # because its sandbox redirects XDG_CONFIG_HOME to ~/.var/app/<id>/config,
  # whose gtk-3.0/ is empty, so it used the host gsettings value instead.
  #
  # GTK_THEME takes precedence over settings.ini, so this fix is local to
  # OrcaSlicer and leaves the (broken) global GTK config untouched. Adwaita-dark
  # already ships in /usr/share/themes, so there is no extra dependency.
  # To use the originally intended look instead, install `pkgs.nordic` and set
  # this to "Nordic-bluish-accent-standard-buttons" (the nixpkgs theme has no
  # `-v40` suffix).
  gtkTheme = "Adwaita-dark";

  orcaFor = pkgs: let
    base = orcaBase pkgs;
  in
    pkgs.symlinkJoin {
      name = "orca-slicer-${base.version}";
      paths = [base];
      nativeBuildInputs = [pkgs.makeWrapper];

      # The package's own bin/orca-slicer is a compiled wrapGAppsHook3 wrapper
      # whose real binary sits beside it as bin/.orca-slicer-wrapped. Do NOT
      # reach for wrapProgram here: it renames the target to .<name>-wrapped and
      # would clobber that 68 MB binary with the 20 KB wrapper. Build a fresh
      # wrapper over the absolute store path instead. That is safe because the
      # gapps wrapper execs bin/.orca-slicer-wrapped by absolute path and the
      # real binary resolves share/OrcaSlicer by absolute path too.
      postBuild = ''
        rm -f $out/bin/orca-slicer
        makeWrapper ${base}/bin/orca-slicer $out/bin/orca-slicer \
          --set GTK_THEME ${gtkTheme}
      '';
    };
in {
  flake.nixosModules.orcaslicer = { pkgs, ... }: {
    environment.systemPackages = [(orcaFor pkgs)];
  };

  # gear5th is Debian, so the shared user layer is what actually installs the
  # app on the machine that owns the profiles.
  #
  # OrcaSlicer keeps presets in a mutable data dir its GUI writes to
  # (`$XDG_CONFIG_HOME/OrcaSlicer`, i.e. ~/.config/OrcaSlicer), the same way
  # ~/.pi holds runtime state. It is deliberately NOT modelled with
  # home.file: Nix owns the binary, the user owns the presets. Upstream only
  # migrates data out of a Flatpak when the app itself runs as a Flatpak (it
  # checks for /.flatpak-info), so the move off the Flatpak was a manual copy.
  flake.homeModules.orcaslicer = { pkgs, ... }: {
    home.packages = [(orcaFor pkgs)];
  };
}
