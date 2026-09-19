{ self, inputs, ... }: {
  flake.nixosModules.zsh = { config, pkgs, lib, ... }: let
    myZsh = self.packages.${pkgs.stdenv.hostPlatform.system}.myZsh;
  in {
    programs.zsh.enable = true;
    programs.zsh.ohMyZsh.enable = true;
    # The plugin packages and the ~/.oh-my-zsh, ~/.zsh/ and ~/powerlevel10k
    # symlinks are owned by flake.homeModules.zsh now (the same implementation
    # gear5th uses), which replaced the bespoke activationScripts this module
    # used to carry. What stays system-side is the login shell and the
    # environment the wrapper needs.
    users.users.ejverat.shell = myZsh;
    environment.sessionVariables = {
      # The wrapper does NOT set ZDOTDIR itself (verified: with the variable
      # unset it comes up empty and zsh reads the wrong dot dirs), so this has
      # to stay system-side.
      ZDOTDIR = myZsh.ZDOTDIR;
      FZF_BASE = "${pkgs.fzf}/share/fzf";
    };
  };

  # Shared user layer for every host (chopper and gear5th). The wrapper package
  # is host-specific — myZsh sources sops-rendered secrets on NixOS while
  # myZshPortable handles the standalone PATH and the tty1 session start — so
  # each host sets nixosConf.zsh.wrapper instead of this module picking one.
  flake.homeModules.zsh = { config, pkgs, lib, ... }: {
    options.nixosConf.zsh.wrapper = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        Host-specific portable zsh wrapper to install. The module provides the
        plugins, the rc-file symlinks and the environment; the wrapper flavor
        comes from the host.
      '';
    };

    config = {
      home.packages =
        with pkgs; [
          fzf
          zsh-autosuggestions
          zsh-syntax-highlighting
          zsh-powerlevel10k
          oh-my-zsh
        ]
        ++ lib.optional (config.nixosConf.zsh.wrapper != null) config.nixosConf.zsh.wrapper;

      # The paths the vendored .zshrc sources, identical on both hosts.
      # Every target path below was verified against the package layout — a wrong
      # subpath here fails silently at shell start ("no such file or directory:
      # ...source:1") instead of at build time, which is how a bad
      # share/zsh/... path shipped unnoticed:
      #   zsh-syntax-highlighting -> $out/share/zsh-syntax-highlighting/…
      #   zsh-autosuggestions    -> $out/share/zsh/plugins/zsh-autosuggestions
      #   powerlevel10k          -> $out/share/zsh/themes/powerlevel10k
      #   oh-my-zsh              -> $out/share/oh-my-zsh
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
        export PATH="$HOME/.local/bin:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"
        # Provider keys: rendered by the shared secrets home module from the age
        # identity derived from ~/.ssh/id_ed25519 — the standalone analogue of
        # chopper's /run/secrets/rendered/pi-provider-keys.env. Sourced from
        # zshenv (not zshrc) so non-interactive shells get the keys too.
        if [ -r "$HOME/.config/pi-provider-keys.env" ]; then
          . "$HOME/.config/pi-provider-keys.env"
        fi
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
