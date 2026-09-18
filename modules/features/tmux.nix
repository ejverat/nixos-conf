{ self, inputs, ... }: {
  flake.nixosModules.tmux = { config, pkgs, lib, ... }: let
    myTmux = self.packages.${pkgs.stdenv.hostPlatform.system}.myTmux;
  in {
    environment.systemPackages = lib.mkBefore [ myTmux ];
  };

  # Portable user layer: the wrapper already sources
  # ~/.dotfiles/config/tmux/tmux.conf (materialized by the dotfiles home
  # module), so installing it into the user profile is enough.
  flake.homeModules.tmux = { pkgs, lib, flakeSelf, ... }: let
    myTmux = flakeSelf.packages.${pkgs.stdenv.hostPlatform.system}.myTmux;
  in {
    home.packages = [ myTmux ];
  };

  perSystem = { pkgs, ... }: {
    packages.myTmux = inputs.wrapper-modules.wrappers.tmux.wrap {
      inherit pkgs;
      terminal = "xterm-256color";
      prefix = "C-a";
      baseIndex = 1;
      modeKeys = "vi";
      visualActivity = false; # image.nvim/molten: keep images stable across tmux windows
      mouse = true;
      plugins = [
        pkgs.tmuxPlugins.nord
        pkgs.tmuxPlugins.session-wizard
      ];
      configAfter = ''
        # Necesario para pi: detección de teclas modificadas (Shift+Enter, etc.)
        set -g extended-keys on
        set -g extended-keys-format csi-u
        source-file ~/.dotfiles/config/tmux/tmux.conf
      '';
    };
  };
}
