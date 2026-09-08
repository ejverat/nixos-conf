{ ... }: {
  flake.nixosModules.pi = { pkgs, ... }: {
    environment.systemPackages = [ pkgs.pi-coding-agent ];
  };
}
