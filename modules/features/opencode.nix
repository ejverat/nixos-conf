{ self, inputs, ... }: {
  flake.nixosModules.opencode = { config, pkgs, lib, ... }: {
    environment.systemPackages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.myOpencode
    ];
  };

  perSystem = { pkgs, ... }: {
    packages.myOpencode = inputs.wrapper-modules.wrappers.opencode.wrap {
      inherit pkgs;
      settings = {
        provider.openrouter.options.apiKey = "{env:OPENROUTER_API_KEY}";
        model = "openrouter/anthropic/claude-sonnet-4-20250514";
        small_model = "openrouter/anthropic/claude-haiku-4-5";
      };
    };
  };
}
