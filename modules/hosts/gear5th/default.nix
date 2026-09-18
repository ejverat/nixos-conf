{
  self,
  inputs,
  ...
}: let
  # gear5th is Debian (non-NixOS): home-manager standalone drives the whole
  # user configuration from this flake's shared home modules. System-level
  # concerns (kernel, drivers, services, boot) stay with Debian.
  system = "x86_64-linux";
  pkgs = import inputs.nixpkgs {
    inherit system;
    # Same policy as the flake-level perSystem pkgs (modules/parts.nix).
    config.allowUnfree = true;
  };

  # Host identity and minimal base. Kept inline (not a separate .nix file):
  # import-tree turns every .nix under modules/ into a flake-parts module, and
  # a home-manager module like this one would be mis-evaluated there.
  hostModule = { pkgs, ... }: {
    home.username = "ejverat";
    home.homeDirectory = "/home/ejverat";
    home.stateVersion = "26.11"; # matches the master home-manager release

    home.packages = with pkgs; [
      git
      ripgrep
    ];

    # Exposes the `home-manager` CLI in the nix profile after the first
    # activation, so later switches are `home-manager switch --flake .#gear5th`.
    programs.home-manager.enable = true;
  };
in {
  flake.homeConfigurations.gear5th = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;

    # The shared feature modules (modules/features/*.nix) are evaluated in
    # home-manager's own module system, which only sees what this call injects.
    # flakeSelf gives them access to this flake's perSystem packages (the
    # wrapper-modules outputs) and flakeInputs their pinned inputs.
    extraSpecialArgs = {
      flakeSelf = self;
      flakeInputs = inputs;
    };

    modules = [
      self.homeModules.dotfiles
      self.homeModules.neovim
      self.homeModules.wezterm
      self.homeModules.tmux
      self.homeModules.zsh
      self.homeModules.niri
      self.homeModules.noctalia
      self.homeModules.pi
      hostModule
    ];
  };
}