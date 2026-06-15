{ self, inputs, ... }: {
  flake.nixosModules.tmux = { config, pkgs, lib, ... }: let
    myTmux = self.packages.${pkgs.stdenv.hostPlatform.system}.myTmux;
  in {
    environment.systemPackages = lib.mkBefore [ myTmux ];
  };

  perSystem = { pkgs, ... }: {
    packages.myTmux = inputs.wrapper-modules.wrappers.tmux.wrap {
      inherit pkgs;
      terminal = "xterm-256color";
      prefix = "C-a";
      baseIndex = 1;
      modeKeys = "vi";
      visualActivity = true;
      mouse = true;
      plugins = [
        pkgs.tmuxPlugins.nord
        pkgs.tmuxPlugins.session-wizard
      ];
      configAfter = ''
        source-file ~/.dotfiles/config/tmux/tmux.conf
      '';
    };
  };
}
