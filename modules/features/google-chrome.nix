{
  # Google Chrome (unfree), shared by both hosts through the user layer.
  #
  # Home-only: the old `flake.nixosModules.google-chrome` only installed the
  # same package system-wide. allowUnfree comes from the flake-level pkgs
  # (modules/lib/_pkgs.nix) and chopper's nixpkgs.config.
  flake.homeModules.google-chrome = {pkgs, ...}: {
    home.packages = [pkgs.google-chrome];
  };
}
