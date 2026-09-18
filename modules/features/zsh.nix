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

  # Portable user layer (non-NixOS hosts, e.g. gear5th/Debian): same plugins
  # and rc files, but nothing root-rendered; the user's .zshrc already sources
  # ~/.config/zsh/secrets.zsh when present. Starts niri from tty1 because no
  # display manager on Debian can load nix-store wayland sessions.
  flake.homeModules.zsh = { pkgs, lib, flakeSelf, ... }: let
    myZshPortable = flakeSelf.packages.${pkgs.stdenv.hostPlatform.system}.myZshPortable;
  in {
    home.packages = with pkgs; [
      myZshPortable
      fzf
      zsh-autosuggestions
      zsh-syntax-highlighting
      zsh-powerlevel10k
      oh-my-zsh
    ];
    # Mirrors chopper's activationScripts.zsh-plugin-symlinks so the same
    # ~/.zshrc sources resolve on both machines.
    home.file = {
      ".oh-my-zsh".source = "${pkgs.oh-my-zsh}/share/oh-my-zsh";
      ".oh-my-zsh-custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.plugin.zsh".text = ''
        source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
      '';
      ".zsh/zsh-autosuggestions".source = "${pkgs.zsh-autosuggestions}/share/zsh/plugins/zsh-autosuggestions";
      "powerlevel10k".source = "${pkgs.zsh-powerlevel10k}/share/zsh/themes/powerlevel10k";
    };
    home.sessionVariables.FZF_BASE = "${pkgs.fzf}/share/fzf";
  };

  perSystem = { pkgs, self', ... }: let
    # Shared: everything both flavors agree on.
    zshCommon = {
      inherit pkgs;
      # User config plugins/aliases come from the vendored dotfiles, same as
      # chopper ($HOME/.dotfiles/home/.zshrc).
      zshrc.content = ''
        export ZSH_CUSTOM="$HOME/.oh-my-zsh-custom"
        typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet
        alias sync-noctalia='nix run ~/nixos-conf#sync-noctalia'
        source "$HOME/.dotfiles/home/.zshrc"
      '';
      skipGlobalRC = true;
      hmSessionVariables = null;
    };
  in {
    packages.myZsh = inputs.wrapper-modules.wrappers.zsh.wrap (zshCommon // {
      zdotFilesDirname = "zsh-dot-dir";
      # Provider API keys come from modules/features/secrets.nix, which renders the
      # sops secrets into this file at activation time. It is sourced from zshenv
      # (not zshrc) so that non-interactive shells get the keys too. This path is
      # hardcoded in exactly two places on purpose; if you move it, also update
      # sops.templates in secrets.nix.
      zshenv.content = ''
        if [ -r /run/secrets/rendered/pi-provider-keys.env ]; then
          . /run/secrets/rendered/pi-provider-keys.env
        fi
      '';
    });

    # Runs niri as the session leader while teeing its full output to
    # $XDG_RUNTIME_DIR/niri-console.log (readable over SSH for diagnosis).
    # exec keeps the script shortlived so tty1 returns to the login prompt
    # when niri exits.
    packages.niri-session-log = pkgs.writeShellScriptBin "niri-session-log" ''
      exec niri 2>&1 | ${pkgs.coreutils}/bin/tee -a "/run/user/$(id -u)/niri-console.log"
    '';

    # Portable flavor for non-NixOS hosts (gear5th/Debian).
    #
    # The nix profile lives under $HOME/.nix-profile (home-manager standalone)
    # and /nix/var/nix/profiles/default (nix installer); prepend both so the
    # wrapped tools (niri, nvim, tmux, wezterm, pi) resolve from a login shell
    # on a machine where /etc/profile does not know about Nix. The user's
    # dotfiles .zshrc sources ~/.config/zsh/secrets.zsh when it exists, so no
    # root-rendered secrets are needed here.
    packages.myZshPortable = inputs.wrapper-modules.wrappers.zsh.wrap (zshCommon // {
      zdotFilesDirname = "zsh-dot-dir-portable";
      zshenv.content = ''
        export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"
        # Minimal PAM service for the noctalia lock screen (created by
        # scripts/fix-pam-unix-chkpwd.sh); the default 'login' stack also works
        # once the setuid unix_chkpwd helper exists.
        export NOCTALIA_PAM_SERVICE="noctalia-lock"
      '';
      zshrc.content = zshCommon.zshrc.content + ''
        # Portable session: no display manager on Debian can launch a
        # nix-store wayland session, so niri takes over tty1 when the login
        # shell is interactive and no display server is already running. Output
        # is teed so a hang is diagnosable over SSH.
        if command -v niri >/dev/null && [[ -z $WAYLAND_DISPLAY && -z $DISPLAY && "$(tty)" = /dev/tty1 ]]; then
          exec ${self'.packages.niri-session-log}/bin/niri-session-log
        fi
      '';
    });
  };
}
