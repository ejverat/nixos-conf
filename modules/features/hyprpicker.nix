{
  # Wayland colour picker, shared by both hosts through the user layer.
  #
  # Home-only: it is a user tool, so there is no system variant. chopper imports
  # this home module instead of a nixosModule (the old
  # `flake.nixosModules.hyprpicker` only installed the same package system-wide).
  flake.homeModules.hyprpicker = {pkgs, ...}: {
    home.packages = [pkgs.hyprpicker];
  };
}
