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

  perSystem = { pkgs, ... }: let
    # tmux loads plugin scripts through `run-shell`, which executes them with
    # `/bin/sh`. On NixOS that is bash, but on Debian (gear5th) it is dash, and
    # nord.tmux depends on bash-only constructs (BASH_SOURCE, `==`). Without a
    # shebang dash tries to interpret it, fails with "Bad substitution", and
    # the theme is never sourced (tmux keeps its default colours). Give it the
    # bash shebang upstream forgot; session-wizard already ships one.
    nord = pkgs.tmuxPlugins.nord.overrideAttrs (old: {
      postInstall = (old.postInstall or "") + ''
        chmod u+w $out/share/tmux-plugins/nord/nord.tmux
        sed -i '1i #!/usr/bin/env bash' $out/share/tmux-plugins/nord/nord.tmux
      '';
    });
  in {
    packages.myTmux = inputs.wrapper-modules.wrappers.tmux.wrap {
      inherit pkgs;
      terminal = "xterm-256color";
      prefix = "C-a";
      baseIndex = 1;
      modeKeys = "vi";
      visualActivity = false; # image.nvim/molten: keep images stable across tmux windows
      mouse = true;
      plugins = [
        nord
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
