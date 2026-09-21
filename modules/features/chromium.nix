{
  # Web browser, shared by both hosts through the user layer.
  #
  # Home-only: the old `flake.nixosModules.chromium` only installed the same
  # package system-wide.
  flake.homeModules.chromium = {pkgs, ...}: {
    home.packages = [pkgs.chromium];
  };
}
