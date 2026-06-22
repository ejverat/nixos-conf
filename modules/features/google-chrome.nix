{ ... }: {
  flake.nixosModules.google-chrome = { pkgs, ... }: {
    environment.systemPackages = [ pkgs.google-chrome ];
  };
}
