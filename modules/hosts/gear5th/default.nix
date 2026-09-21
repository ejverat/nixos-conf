{
  self,
  inputs,
  ...
}: let
  # gear5th is Debian (non-NixOS): home-manager standalone drives the whole
  # user configuration from this flake's shared home modules. System-level
  # concerns (kernel, drivers, services, boot) stay with Debian.
  system = "x86_64-linux";
  # Shared manual-import policy (allowUnfree). See modules/lib/_pkgs.nix.
  pkgs = (import ../../lib/_pkgs.nix) inputs.nixpkgs system;

  # Host identity and minimal base. Kept inline (not a separate .nix file):
  # import-tree turns every .nix under modules/ into a flake-parts module, and
  # a home-manager module like this one would be mis-evaluated there.
  hostModule = { pkgs, flakeSelf, ... }: {
    # The shared zsh module provides plugins/rc symlinks; the standalone host
    # installs the portable wrapper (it is also the login shell binary, so it
    # must stay in this profile for GC safety).
    nixosConf.zsh.wrapper =
      flakeSelf.packages.${pkgs.stdenv.hostPlatform.system}.myZshPortable;

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
      self.homeModules.gh
      self.homeModules.hyprpicker
      self.homeModules.neovim
      self.homeModules.wezterm
      self.homeModules.tmux
      self.homeModules.zsh
      self.homeModules.niri
      self.homeModules.noctalia
      self.homeModules.pi
      # Provider keys: sops decrypted as the user with the age identity derived
      # from ~/.ssh/id_ed25519, rendered to ~/.config/pi-provider-keys.env (the
      # portable zsh sources it) instead of chopper's root-rendered /run/secrets.
      self.homeModules.secrets
      # Nix-built pi ecosystem: gentle-pi (harness) and engram (memory). The
      # activations merge the store paths into ~/.pi/agent/settings.json, which
      # pi owns at runtime, exactly like chopper's system activations do.
      self.homeModules.gentle-pi
      self.homeModules.engram
      # Native OrcaSlicer 2.4.2 from the dedicated nixpkgs-orca pin, replacing
      # the Flatpak install that owned the print profiles.
      self.homeModules.orcaslicer
      hostModule
    ];
  };
}