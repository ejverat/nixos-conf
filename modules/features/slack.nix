{ ... }: {
  flake.nixosModules.slack = { pkgs, ... }: {
    environment.systemPackages = [ pkgs.slack ];
  };
}
