{ ... }: {
  # Share the user's PrusaSlicer presets between hosts, the same way OrcaSlicer's
  # are shared.
  #
  # Only the four preset directories are involved. Everything else in
  # PrusaSlicer's config directory is deliberately out of scope: `cache/` is
  # derived state the application rebuilds (112 files appeared there on the first
  # launch), and `PrusaSlicer.ini`, `workflows.json` and
  # `ArchiveRepositoryManifest.json` are application state rather than presets.
  #
  # The seed never overwrites, so a preset edited in the GUI always wins, and the
  # same one caveat applies: the vendored printer preset references two local bed
  # assets by absolute path (`pros1_bed.stl` and `kp3s-alt1.svg` under `~/LDATA`).
  # Those are not in this repository, so on a host that lacks them the custom bed
  # simply will not render. Optional, not fatal, but worth knowing before it looks
  # like a mystery.
  flake.homeModules.prusaslicer-presets = { config, lib, ... }: {
    home.activation.prusaPresetSeed = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      import ../lib/_preset-seed.nix {
        homeDir = config.home.homeDirectory;
        vendored = ../../dotfiles/prusaslicer/presets;
        destination = "PrusaSlicer";
      }
    );
  };
}
