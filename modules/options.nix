{
  # Cross-cutting host options read by the feature modules. Declared here (not
  # inside a feature file) so a NixOS host sets them once and every feature
  # consumes the same source of truth.
  #
  # The home-manager modules do not need these: they already resolve the user
  # through config.home.username / config.home.homeDirectory.
  flake.nixosModules.nixosConf = {lib, ...}: {
    options.nixosConf.user.name = lib.mkOption {
      type = lib.types.str;
      description = ''
        Primary desktop user. Feature modules derive the home directory and the
        file ownership from it (config.users.users.<name>.home), so the literal
        lives only in the host that creates the account.
      '';
    };
  };
}
