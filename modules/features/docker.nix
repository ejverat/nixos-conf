{ ... }: {
  flake.nixosModules.docker = { config, pkgs, lib, ... }: {
    virtualisation.docker = {
      enable = true;
      rootless = {
        enable = true;
        setSocketVariable = true;
      };
    };

    users.users.ejverat.extraGroups = [ "docker" ];
  };
}
