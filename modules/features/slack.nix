{
  # Slack desktop, shared by both hosts through the user layer.
  #
  # Home-only: the old `flake.nixosModules.slack` only installed the same
  # package system-wide.
  flake.homeModules.slack = {pkgs, ...}: {
    home.packages = [pkgs.slack];
  };
}
