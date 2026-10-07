{
  # kanshi: output/monitor profile daemon, shared by both hosts through the
  # user layer.
  #
  # The config is host-specific, so it is an option:
  #   - declared per host through `nixosConf.kanshi.config` (chopper, whose
  #     laptop + dock profiles are known);
  #   - left unset (the default) elsewhere, in which case the module still
  #     installs the package and the user service and the config stays
  #     user-owned runtime state at ~/.config/kanshi/config (like the OrcaSlicer
  #     presets or ~/.pi) for gear5th, a fixed-monitor desktop.
  #
  # Home-only: the old `flake.nixosModules.kanshi` installed the package
  # system-wide and read /etc/kanshi/config; chopper now uses this module and
  # kanshi's default config path.
  flake.homeModules.kanshi = {config, lib, pkgs, ...}: {
    options.nixosConf.kanshi.config = lib.mkOption {
      type = lib.types.nullOr lib.types.lines;
      default = null;
      description = ''
        Declarative kanshi config text. When null, the config is not managed by
        Nix and stays user-owned at ~/.config/kanshi/config.
      '';
    };

    config = {
      home.packages = [pkgs.kanshi];

      xdg.configFile."kanshi/config" = lib.mkIf (config.nixosConf.kanshi.config != null) {
        text = config.nixosConf.kanshi.config;
      };

      systemd.user.services.kanshi = {
        Unit = {
          Description = "Kanshi output management daemon";
          # The config is optional by design: a host that leaves
          # nixosConf.kanshi.config unset (gear5th) keeps it user-owned, and may
          # never create it. Without this guard kanshi exits with "failed to
          # parse config file" and Restart=on-failure loops every 5s forever
          # (observed: restart counter 16022). ConditionPathExists makes the
          # unit *skip* instead of *fail* when the file is absent, so the
          # daemon starts normally once the user creates the config.
          ConditionPathExists = "%h/.config/kanshi/config";
        };
        Service = {
          # No -c: kanshi reads $XDG_CONFIG_HOME/kanshi/config (i.e.
          # ~/.config/kanshi/config), which is what xdg.configFile writes or the
          # user owns.
          ExecStart = lib.getExe pkgs.kanshi;
          Restart = "on-failure";
          RestartSec = "5s";
        };
        Install.WantedBy = ["default.target"];
      };
    };
  };
}
