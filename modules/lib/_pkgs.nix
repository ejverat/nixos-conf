# Single place for the manual nixpkgs imports that need allowUnfree.
#
# The NixOS host sets its own `nixpkgs.config.allowUnfree` through the module
# system (the native way), so this helper covers the three manual imports that
# used to repeat the policy: the flake-level perSystem pkgs (modules/parts.nix),
# the standalone gear5th pkgs (modules/hosts/gear5th), and the dedicated orca
# pin (modules/features/orcaslicer.nix).
#
# Lives under modules/lib/ with a leading underscore: import-tree skips paths
# containing "/_", so it is not evaluated as a flake-parts module.
nixpkgs: system:
import nixpkgs {
  inherit system;
  config.allowUnfree = true;
}
