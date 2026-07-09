{ ... }: {
  flake.nixosModules.hyprpicker = { pkgs, ... }: {
    environment.systemPackages = [ pkgs.hyprpicker ];
  };
}
