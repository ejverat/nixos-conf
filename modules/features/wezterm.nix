{ ... }: {
  flake.nixosModules.wezterm = { pkgs, ... }: {
    environment.systemPackages = [ pkgs.wezterm ];
  };
}
