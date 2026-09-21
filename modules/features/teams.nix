{
  # Microsoft Teams, shared by both hosts through the user layer. nixpkgs wraps
  # the official client as `teams-for-linux`.
  #
  # Home-only: the old `flake.nixosModules.teams` only installed the same
  # package system-wide.
  flake.homeModules.teams = {pkgs, ...}: {
    home.packages = [pkgs.teams-for-linux];
  };
}
