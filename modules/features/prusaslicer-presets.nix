{ ... }: {
  # Share the user's PrusaSlicer presets and the bed assets they depend on,
  # between hosts: the same treatment OrcaSlicer's presets already get.
  #
  # Only the four preset directories are shared. Everything else in PrusaSlicer's
  # config directory is deliberately out of scope: `cache/` is derived state the
  # application rebuilds (112 files appeared there on the first launch), and
  # `PrusaSlicer.ini`, `workflows.json` and `ArchiveRepositoryManifest.json` are
  # application state rather than presets.
  #
  # ## Presets are seeded; assets are linked
  #
  # The split is the one this repository already turns on for dotfiles, applied
  # per file kind:
  #
  #   - **Presets are seeded** (copied on activation, never overwritten) because
  #     the application rewrites them: they are mutable runtime state, and a
  #     store path is read-only, so linking them would break the application the
  #     moment it tried to save a preset the user edited.
  #   - **The bed assets are linked** with `home.file` because the application
  #     only ever reads them. A link cannot drift from the pinned upstream
  #     revision, and there is nothing for the application to write.
  #
  # ## Why the assets are fetched rather than vendored
  #
  # They are **not** the user's work: they come from `github.com/RyanT95/KP3S-Prusa`,
  # distributed under **Creative Commons Attribution-NonCommercial 4.0
  # International**, and this repository is public. Vendoring them would mean
  # republishing third-party material, so they are fetched from a pinned upstream
  # revision instead. That keeps third-party content out of the repository,
  # leaves the licence and the provenance with the source they came from, and
  # makes the revision auditable.
  #
  # Revision `2b5f86f2e7e1e9a345c5da91f400604e3778cdef` was chosen after checking
  # that both assets there are **byte-identical** to the copies the user had
  # already been slicing against, so this cannot change the bed.
  #
  # ## They live inside the config directory, and the presets point there
  #
  # The assets are placed in `~/.config/PrusaSlicer/bed-assets/` so the whole
  # PrusaSlicer setup stays in one place instead of reaching into the user's
  # `~/LDATA` tree. Because a preset references them by **absolute path**, moving
  # them meant repointing the presets, and not only the vendored copies: the seed
  # never overwrites, so editing only the repository copy would have left the
  # host still reading the old location. Both were changed together.
  #
  # That absolute path embeds the user name. Fine here, because both hosts run
  # the same account; a host with a different one would need its preset
  # repointed.
  flake.homeModules.prusaslicer-presets = { config, lib, pkgs, ... }: let
    upstream = pkgs.fetchFromGitHub {
      owner = "RyanT95";
      repo = "KP3S-Prusa";
      rev = "2b5f86f2e7e1e9a345c5da91f400604e3778cdef";
      hash = "sha256-XcqaaZIIBws7yCokc24kKzZIfkKtWZ4F7oPFO3ez7+0=";
    };

    # Only the two referenced files, so nothing else from the bundle lands on
    # disk.
    bedAssets = pkgs.runCommand "kp3s-pros1-bed-assets" {} ''
      mkdir -p $out
      install -m 0644 ${upstream}/Kingroon/pros1_bed.stl $out/pros1_bed.stl
      install -m 0644 ${upstream}/Kingroon/kp3s-alt1.svg $out/kp3s-alt1.svg
    '';
  in {
    home.activation.prusaPresetSeed = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      import ../lib/_preset-seed.nix {
        src = ../../dotfiles/prusaslicer/presets;
        dst = "${config.home.homeDirectory}/.config/PrusaSlicer";
      }
    );

    home.file = {
      ".config/PrusaSlicer/bed-assets/pros1_bed.stl".source = "${bedAssets}/pros1_bed.stl";
      ".config/PrusaSlicer/bed-assets/kp3s-alt1.svg".source = "${bedAssets}/kp3s-alt1.svg";
    };
  };
}
