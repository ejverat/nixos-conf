{ inputs, ... }: {
  systems = [
    "x86_64-linux"
    "x86_64-darwin"
    "aarch64-linux"
    "aarch64-darwin"
  ];

  perSystem = { system, ... }: {
    # Build the flake-level packages (wrapperModules wrappers) with
    # `allowUnfree` enabled, matching `nixpkgs.config.allowUnfree = true`
    # in the host configuration. Some wrappers depend on unfree tools
    # (e.g. `replace`, used by wrapperModules' symlinkScript).
    _module.args.pkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
  };
}
