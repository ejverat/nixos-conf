{ self, inputs, ... }: {
  flake.nixosModules.zsh = { config, pkgs, lib, ... }: let
    myZsh = self.packages.${pkgs.stdenv.hostPlatform.system}.myZsh;
  in {
    programs.zsh.enable = true;
    users.users.ejverat.shell = myZsh;
    environment.sessionVariables.ZDOTDIR = myZsh.ZDOTDIR;
  };

  perSystem = { pkgs, ... }: {
    packages.myZsh = inputs.wrapper-modules.wrappers.zsh.wrap {
      inherit pkgs;
      zdotFilesDirname = "zsh-dot-dir";
      zshrc.content = ''
        source "$HOME/.dotfiles/home/.zshrc"
      '';
      skipGlobalRC = true;
      hmSessionVariables = null;
    };
  };
}
