{ ... }: {
  # Native FreeCAD on gear5th.
  #
  # From the **main** nixpkgs pin, which ships 1.1.3 — exact parity with the
  # Flatpak being replaced — so no dedicated pin. Same reasoning as PrusaSlicer:
  # the `nixpkgs-orca` pin exists because OrcaSlicer lagged a minor version, and it
  # is the exception rather than the pattern. Every other application on this host
  # already comes from the main pin.
  #
  # No GTK theme module here, and unlike the slicers that is not an oversight:
  # **FreeCAD is a Qt application**, so `flake.homeModules.gtk` does nothing for it.
  # Its appearance on a session with no Qt platform theme is tracked as a follow-up
  # in odd/tasks/freecad-native.md rather than solved here, because the `qt6ct`
  # available on this host is a Debian package whose platform-theme plugin would
  # have to be ABI-compatible with the nix Qt build, and mixing the two is the kind
  # of fragility worth avoiding. Fixing it belongs in a per-application wrapper, as
  # OrcaSlicer used, not in a session-wide variable — on gear5th that is the
  # mechanism that has already taken the session down twice.
  #
  # FreeCAD keeps its user state in its own config and data directories
  # (`~/.config/FreeCAD` and `~/.local/share/FreeCAD`), i.e. user-owned runtime
  # state the application rewrites, so nothing is modelled with `home.file`: Nix
  # owns the binary, the user owns the preferences, the addons and the preference
  # packs. Note that 1.1 keeps most of it under a versioned `v1-1/` subtree.
  flake.nixosModules.freecad = { pkgs, ... }: {
    environment.systemPackages = [pkgs.freecad];
  };

  flake.homeModules.freecad = { pkgs, ... }: {
    home.packages = [pkgs.freecad];
  };
}
