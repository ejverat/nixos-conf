{ ... }: {
  flake.nixosModules.docker = { config, pkgs, lib, ... }: {
    virtualisation.docker = {
      enable = true;
      rootless = {
        enable = true;
        setSocketVariable = true;
      };
    };

    users.users.${config.nixosConf.user.name}.extraGroups = [ "docker" ];
  };
}
