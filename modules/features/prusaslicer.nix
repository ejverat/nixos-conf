{ ... }: {
  # Native PrusaSlicer on gear5th.
  #
  # Taken from the **main** nixpkgs pin, which is the same one every other
  # application on this host already uses (gimp, libreoffice, chromium), and
  # which ships **2.9.6** — exact parity with the Flatpak being replaced. There
  # is therefore no version argument for a dedicated pin here. The `nixpkgs-orca`
  # pin exists only because OrcaSlicer lagged a minor version (2.3.2 against
  # 2.4.2); it is not the general pattern, and adding a second consumer to a pin
  # named after a different application would either make that name a lie or
  # force a rename of merged code.
  #
  # No GTK work belongs here: `flake.homeModules.gtk` already gives every GTK 3
  # application on this host the Nordic theme with `prefer-dark`, and PrusaSlicer
  # is GTK 3. OrcaSlicer only needed a per-app workaround because the global
  # configuration was broken at the time.
  #
  # PrusaSlicer keeps its presets and its `PrusaSlicer.ini` in its own config
  # directory, i.e. the same user-owned runtime state shape as OrcaSlicer's, so
  # nothing is modelled with `home.file`: Nix owns the binary, the user owns the
  # presets.
  #
  # If this package ever needs to be wrapped, use `symlinkJoin` + `makeWrapper`
  # over the absolute store path and **never** `wrapProgram`. The package has the
  # same layout as OrcaSlicer's: `bin/prusa-slicer` is a 16 KB compiled
  # `wrapGAppsHook3` wrapper whose real 43 MB binary is
  # `bin/.prusa-slicer-wrapped`. `wrapProgram` renames its target to
  # `.<name>-wrapped`, which is exactly that name, and would overwrite the real
  # binary with the wrapper.
  flake.nixosModules.prusaslicer = { pkgs, ... }: {
    environment.systemPackages = [pkgs.prusa-slicer];
  };

  flake.homeModules.prusaslicer = { pkgs, ... }: {
    home.packages = [pkgs.prusa-slicer];
  };
}
