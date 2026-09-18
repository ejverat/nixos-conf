{ ... }: {
  flake.nixosModules.wezterm = { pkgs, ... }: {
    environment.systemPackages = [ pkgs.wezterm ];
  };

  # Portable user layer: same package plus the config materialized at
  # ~/.config/wezterm (vendored from dotfiles/config/wezterm).
  flake.homeModules.wezterm = { pkgs, ... }: {
    home.packages = [ pkgs.wezterm ];
    xdg.configFile."wezterm/wezterm.lua".source = ../../dotfiles/config/wezterm/wezterm.lua;
  };
}
