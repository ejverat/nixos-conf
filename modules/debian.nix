{ self, inputs, ... }: {
  perSystem = { pkgs, lib, system, self', ... }: let
    inherit (self'.packages) myNeovim myTmux myZsh myNiri myNoctalia myOpencode;
    claudeCodePkg = inputs.claude-code.packages.${system}.default;
  in {
    packages.debian-bundle = pkgs.buildEnv {
      name = "debian-bundle";
      paths = [
        # ── Wrapped packages from this flake ──
        myNeovim
        myTmux
        myZsh
        myNiri
        myNoctalia
        myOpencode
        claudeCodePkg

        # ── Browsers ──
        pkgs.chromium
        pkgs.google-chrome
        pkgs.firefox

        # ── Terminals ──
        pkgs.wezterm
        pkgs.alacritty

        # ── Editors & dev tools ──
        pkgs.git
        pkgs.gcc
        pkgs.ripgrep
        pkgs.luarocks
        pkgs.tree
        pkgs.fzf
        pkgs.bat
        pkgs.fd-find
        pkgs.direnv

        # ── Graphics / media ──
        pkgs.gimp
        pkgs.feh
        pkgs.nomacs
        pkgs.imagemagick
        pkgs.hyprpicker
        pkgs.kanshi

        # ── File management ──
        pkgs.thunar
        pkgs.thunar-archive-plugin
        pkgs.thunar-volman
        pkgs.file-roller

        # ── Communication ──
        pkgs.slack

        # ── System utils ──
        pkgs.pciutils
        pkgs.upower
        pkgs.docker-client
        pkgs.ollama
      ];
      ignoreCollisions = true;
    };
  };
}
