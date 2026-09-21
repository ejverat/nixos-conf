{ inputs, ... }: let
  # OrcaSlicer from the dedicated `nixpkgs-orca` pin: the main nixpkgs pin
  # still ships 2.3.2, and the user's print profiles come from a 2.4.2
  # Flatpak. Rationale and tradeoff: odd/tasks/orcaslicer-native.md.
  #
  # `allowUnfree` comes from the shared manual-import helper (modules/lib/_pkgs.nix),
  # the same policy the flake-level perSystem pkgs and gear5th's pkgs use.
  # orca-slicer itself is AGPL-3.0 (free); the flag is there so the closure
  # does not start failing if a dependency ever needs it.
  orcaFor = pkgs:
    ((import ../lib/_pkgs.nix) inputs.nixpkgs-orca pkgs.stdenv.hostPlatform.system)
    .orca-slicer;
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
  #
  # This used to carry a per-app `GTK_THEME` wrapper because the app opened
  # light while its Flatpak predecessor opened dark. That was a symptom: the
  # real cause was that no GTK theme could be resolved on this host at all, and
  # it is fixed at the source by `flake.homeModules.gtk`. Wrapping the app only
  # for itself would leave it the one GTK application on the machine pinned to
  # a different theme, and would silently override any later theme change, so
  # the wrapper is deliberately gone. If OrcaSlicer ever needs to diverge
  # again, reinstate it as a `symlinkJoin` + `makeWrapper` here — never with
  # `wrapProgram`, which renames its target to `.<name>-wrapped` and would
  # clobber the package's real 68 MB `bin/.orca-slicer-wrapped` binary.
  flake.homeModules.orcaslicer = { pkgs, ... }: {
    home.packages = [(orcaFor pkgs)];
  };
}
