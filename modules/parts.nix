{ inputs, ... }: let
  # Shared manual-import policy (allowUnfree). See modules/lib/_pkgs.nix.
  mkPkgs = import ./lib/_pkgs.nix;
in {
  # home-manager flake-parts integration: makes `flake.homeModules` (shared
  # user configuration used by standalone hosts like gear5th/Debian) and
  # `flake.homeConfigurations` mergeable, dendritic-style.
  imports = [ inputs.home-manager.flakeModules.default ];

  systems = [
    "x86_64-linux"
    "x86_64-darwin"
    "aarch64-linux"
    "aarch64-darwin"
  ];

  perSystem = { system, ... }: {
    # Build the flake-level packages (wrapperModules wrappers) with
    # `allowUnfree` enabled, matching `nixpkgs.config.allowUnfree = true`
    # in the host configuration. Some wrappers depend on unfree tools
    # (e.g. `replace`, used by wrapperModules' symlinkScript).
    _module.args.pkgs = mkPkgs inputs.nixpkgs system;
  };
}
