{ ... }: {
  # Materializes the portable dotfiles at the exact ~/.dotfiles paths the
  # wrapper-modules packages reference at runtime on chopper:
  #   - nvim:   nvim wrapper config_directory is $HOME/.dotfiles/config/nvim
  #   - tmux:   myTmux configAfter sources ~/.dotfiles/config/tmux/tmux.conf
  #   - zsh:    myZsh zshrc sources $HOME/.dotfiles/home/.zshrc
  #   - tmux:   cht.sh shortcut spawns ~/.dotfiles/utilities/cht.sh
  # Keeping the same paths on non-NixOS hosts means the exact same wrapper
  # packages run on both machines. Chopper still uses its manual ~/.dotfiles
  # clone until it migrates to this module (phase 2).
  flake.homeModules.dotfiles = { ... }: {
    home.file = {
      ".dotfiles/config/nvim" = {
        source = ../../dotfiles/config/nvim;
        recursive = true;
      };
      ".dotfiles/config/tmux" = {
        source = ../../dotfiles/config/tmux;
        recursive = true;
      };
      ".dotfiles/config/wezterm" = {
        source = ../../dotfiles/config/wezterm;
        recursive = true;
      };
      ".dotfiles/home/.zshrc".source = ../../dotfiles/home/.zshrc;
      ".dotfiles/utilities/cht.sh" = {
        source = ../../dotfiles/utilities/cht.sh;
        executable = true;
      };
    };
  };
}