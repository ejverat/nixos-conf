{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";

    wrapper-modules.url = "github:BirdeeHub/nix-wrapper-modules";

    opencode.url = "github:GutMutCode/opencode-nix";

    claude-code.url = "github:sadjow/claude-code-nix";

    antigravity-nix = {
      url = "github:jacopone/antigravity-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mermaid-rs-renderer = {
      url = "github:1jehuang/mermaid-rs-renderer";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs-pnpm = {
      url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    };

    # Pinned separately so pi-coding-agent stays new enough for gentle-pi
    # (requires >= 0.85.1) without updating the whole system nixpkgs.
    nixpkgs-pi = {
      url = "github:NixOS/nixpkgs/nixos-unstable";
    };

    # Pinned separately because the main nixpkgs pin still ships
    # orca-slicer 2.3.2 while upstream is on 2.4.2, and the user's print
    # profiles come from a 2.4.2 Flatpak install. Do not let this pin follow
    # the main nixpkgs: following it would defeat the point of the extra pin.
    # Cost: the package carries its own dependency closure (webkitgtk,
    # wxwidgets, ...) isolated from the main pin. Acceptable because
    # orca-slicer 2.4.2 is in the binary cache, so nothing is compiled.
    nixpkgs-orca = {
      url = "github:NixOS/nixpkgs/nixos-unstable";
    };

    # Secret management. Age identity is the ed25519 SSH host key
    # (services.openssh.enable is on, and sops.age.sshKeyPaths defaults to it),
    # so there is no separate age key to generate or keep.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home-manager standalone: portable user configuration on non-NixOS hosts
    # (gear5th/Debian) and the target layer for migrating chopper's user-level
    # features later. Modules live in modules/features/* as flake.homeModules.*
    # and the Debian host is modules/hosts/gear5th.
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake {inherit inputs;} (inputs.import-tree ./modules);
}
