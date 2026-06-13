{ self, inputs, lib, ... }: {
  flake.nixosModules.wezterm = { config, pkgs, ... }: {
    environment.systemPackages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.myWezterm
    ];
  };

  perSystem = { pkgs, ... }: {
    packages.myWezterm = inputs.wrapper-modules.wrappers.wezterm.wrap {
      inherit pkgs;
      luaInfo = {
        font_size = 12.0;
        color_scheme = "Catppuccin Mocha";
      };
    };
  };
}
