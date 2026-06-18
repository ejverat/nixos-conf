{ inputs, ... }: {
  flake.nixosModules.claude-code = { pkgs, ... }: {
    nixpkgs.overlays = [ inputs.claude-code.overlays.default ];
    environment.systemPackages = [ pkgs.claude-code ];
  };
}
