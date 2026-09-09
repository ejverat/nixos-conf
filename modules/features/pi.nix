{ inputs, ... }: {
  flake.nixosModules.pi = { pkgs, ... }: {
    # pi-coding-agent from the dedicated nixpkgs-pi pin: gentle-pi requires
    # pi >= 0.85.1 while the main nixpkgs pin still ships an older release.
    environment.systemPackages = [
      inputs.nixpkgs-pi.legacyPackages.${pkgs.stdenv.hostPlatform.system}.pi-coding-agent
    ];
  };
}
