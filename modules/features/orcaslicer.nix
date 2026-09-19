{ inputs, ... }: let
  # OrcaSlicer from the dedicated `nixpkgs-orca` pin: the main nixpkgs pin
  # still ships 2.3.2, and the user's print profiles come from a 2.4.2
  # Flatpak. Rationale and tradeoff: odd/tasks/orcaslicer-native.md.
  #
  # `allowUnfree` mirrors the flake-level perSystem pkgs and gear5th's pkgs.
  # orca-slicer itself is AGPL-3.0 (free); the flag is there so the closure
  # does not start failing if a dependency ever needs it.
  orcaFor = pkgs:
    (import inputs.nixpkgs-orca {
      inherit (pkgs.stdenv.hostPlatform) system;
      config.allowUnfree = true;
    }).orca-slicer;
in {
  flake.nixosModules.orcaslicer = { pkgs, ... }: {
    environment.systemPackages = [ (orcaFor pkgs) ];
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
    home.packages = [ (orcaFor pkgs) ];
  };
}
