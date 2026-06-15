{ self, inputs, ... }: {
  flake.nixosModules.zsh = { config, pkgs, lib, ... }: let
    myZsh = self.packages.${pkgs.stdenv.hostPlatform.system}.myZsh;
  in {
    programs.zsh.enable = true;
    programs.zsh.ohMyZsh.enable = true;
    environment.systemPackages = with pkgs; [
      zsh-autosuggestions
      zsh-powerlevel10k
      zsh-syntax-highlighting
      fzf
      tmux
    ];
    users.users.ejverat.shell = myZsh;
    environment.sessionVariables = {
      ZDOTDIR = myZsh.ZDOTDIR;
      FZF_BASE = "${pkgs.fzf}/share/fzf";
    };

    system.activationScripts.zsh-plugin-symlinks = {
      text = ''
        # oh-my-zsh
        ln -sfn ${pkgs.oh-my-zsh}/share/oh-my-zsh /home/ejverat/.oh-my-zsh
        # custom plugins dir for nix-managed third-party plugins
        mkdir -p /home/ejverat/.oh-my-zsh-custom/plugins
        rm -rf /home/ejverat/.oh-my-zsh-custom/plugins/zsh-syntax-highlighting
        mkdir -p /home/ejverat/.oh-my-zsh-custom/plugins/zsh-syntax-highlighting
        cat > /home/ejverat/.oh-my-zsh-custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.plugin.zsh << EOF
source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
EOF
        # legacy paths for direct sourcing in user's .zshrc
        mkdir -p /home/ejverat/.zsh
        rm -rf /home/ejverat/.zsh/zsh-autosuggestions
        ln -sfn ${pkgs.zsh-autosuggestions}/share/zsh/plugins/zsh-autosuggestions /home/ejverat/.zsh/zsh-autosuggestions
        rm -rf /home/ejverat/powerlevel10k
        ln -sfn ${pkgs.zsh-powerlevel10k}/share/zsh/themes/powerlevel10k /home/ejverat/powerlevel10k
      '';
      deps = [ "users" ];
    };
  };

  perSystem = { pkgs, ... }: {
    packages.myZsh = inputs.wrapper-modules.wrappers.zsh.wrap {
      inherit pkgs;
      zdotFilesDirname = "zsh-dot-dir";
      zshrc.content = ''
        export ZSH_CUSTOM="$HOME/.oh-my-zsh-custom"
        typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet
        source "$HOME/.dotfiles/home/.zshrc"
      '';
      skipGlobalRC = true;
      hmSessionVariables = null;
    };
  };
}
