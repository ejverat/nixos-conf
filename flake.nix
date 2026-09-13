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

    # Secret management. Age identity is the ed25519 SSH host key
    # (services.openssh.enable is on, and sops.age.sshKeyPaths defaults to it),
    # so there is no separate age key to generate or keep.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake {inherit inputs;} (inputs.import-tree ./modules);
}
