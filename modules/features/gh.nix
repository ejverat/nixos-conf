{
  # GitHub CLI on both hosts through the shared user layer. Auth state
  # (~/.config/gh/hosts.yml) is user data, like ~/.pi: Nix installs the binary,
  # the user logs in once per machine. git is already present on both hosts.
  flake.homeModules.gh = {pkgs, ...}: {
    home.packages = [pkgs.gh];
  };
}
