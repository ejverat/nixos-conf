{ inputs, ... }: {
  flake.nixosModules.antigravity = { pkgs, ... }: {
    nixpkgs.overlays = [ inputs.antigravity-nix.overlays.default ];
    environment.systemPackages = [
      pkgs.google-antigravity
      pkgs.google-antigravity-ide
      pkgs.google-antigravity-cli
    ];
  };
}
