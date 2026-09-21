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
  # ## The bed assets, and why they are fetched rather than vendored
  #
  # The vendored printer preset references two bed assets by absolute path, so
  # copying the preset alone leaves a preset whose custom bed silently does not
  # render. They are **not** the user's work: they come from
  # `github.com/RyanT95/KP3S-Prusa`, distributed under
  # **Creative Commons Attribution-NonCommercial 4.0 International**.
  #
  # Vendoring them would mean republishing third-party material in this
  # repository, which is public, so they are fetched from the pinned upstream
  # revision instead. That keeps third-party content out of the repository,
  # leaves the licence and the provenance with the source it came from, and makes
  # the exact revision auditable in `flake.lock`-style terms.
  #
  # Revision `2b5f86f2e7e1e9a345c5da91f400604e3778cdef` was chosen after checking
  # that both assets there are **byte-identical** to the copies already in use on
  # gear5th (`956dd6c7…` for the STL and `31b5fad6…` for the SVG), so this cannot
  # change the bed the user has been slicing against.
  #
  # The destination is the exact path the preset references. If that preset ever
  # points somewhere else, this destination has to follow it — the alternative
  # would be rewriting the preset, which conflicts with the seed's
  # never-overwrite policy.
  flake.homeModules.prusaslicer-presets = { config, lib, pkgs, ... }: let
    home = config.home.homeDirectory;

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
        inherit lib;
        seeds = [
          {
            src = ../../dotfiles/prusaslicer/presets;
            dst = "${home}/.config/PrusaSlicer";
          }
          {
            src = bedAssets;
            dst = "${home}/LDATA/3DPrint/KP3SProS1/Configs/KP3S-Prusa-main/Kingroon";
          }
        ];
      }
    );
  };
}
