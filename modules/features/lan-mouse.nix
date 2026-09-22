{
  # lan-mouse: software KVM (one mouse and keyboard across two machines over the
  # LAN), shared by both hosts through the user layer.
  #
  # Why lan-mouse and not Deskflow / Input Leap / Synergy 3: those resolve
  # Wayland through libei (an EIS server on the compositor) or through the
  # xdg-desktop-portal RemoteDesktop/InputCapture interfaces, and niri
  # implements neither (upstream issues niri#823, niri#1966 and niri#4228 are
  # still open). What niri does implement is the wlroots input protocol set:
  # `wlr-virtual-pointer` + `virtual-keyboard` for injection and `layer-shell` +
  # `pointer-constraints` for capture, which is exactly what lan-mouse's
  # `wlroots` emulation and `layer-shell` capture backends need. The tool-by-tool
  # evidence is recorded in odd/tasks/lan-mouse-kvm.md.
  #
  # Nothing has to be overridden to get those backends: lan-mouse's default cargo
  # features are `layer_shell_capture` and `wlroots_emulation`, and the nixpkgs
  # build carries both (verified against the built binary).
  flake.nixosModules.lan-mouse = {pkgs, ...}: {
    environment.systemPackages = [pkgs.lan-mouse];

    # lan-mouse listens for peers on UDP 4242 (DTLS, every peer pinned by
    # fingerprint). The port is declared here instead of in the host file because
    # it is part of this feature's contract: dropping the import closes the port
    # again. This is the deliberate exception to hosts owning their firewall
    # lines.
    networking.firewall.allowedUDPPorts = [4242];
  };

  flake.homeModules.lan-mouse = {config, lib, pkgs, ...}: {
    options.nixosConf.lan-mouse.config = lib.mkOption {
      type = lib.types.nullOr lib.types.lines;
      default = null;
      description = ''
        Initial lan-mouse config.toml text, seeded into
        ~/.config/lan-mouse/config.toml only when that file does not exist yet.
        When null (the default) nothing is seeded and the file stays user-owned.
      '';
    };

    config = {
      home.packages = [pkgs.lan-mouse];

      # Seed, never link: lan-mouse rewrites config.toml when a peer is
      # authorized (it persists `authorized_fingerprints` there) and a store path
      # is read-only, so managing the file with `xdg.configFile` would break the
      # authorization flow. Same policy as the slicer presets
      # (modules/lib/_preset-seed.nix): copy only when missing, so the
      # application's own file always wins over the seeded one.
      home.activation.lanMouseConfigSeed = lib.mkIf (config.nixosConf.lan-mouse.config != null) (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          seed=${pkgs.writeText "lan-mouse-config.toml" config.nixosConf.lan-mouse.config}
          dst="$HOME/.config/lan-mouse/config.toml"
          if [ -e "$dst" ]; then
            echo "lan-mouse: keeping the existing $dst (the seed never overwrites)"
          else
            mkdir -p "$(dirname "$dst")"
            install -m 0644 "$seed" "$dst"
            echo "lan-mouse: seeded $dst"
          fi
        ''
      );

      # Upstream ships this unit (service/lan-mouse.service). The daemon injects
      # input through the compositor, so it needs an active graphical session:
      # that is why it is bound to graphical-session.target instead of using
      # kanshi's default.target. The GUI (or `lan-mouse cli`) attaches to the
      # running daemon over its socket, and that is how a peer gets authorized
      # the first time.
      systemd.user.services.lan-mouse = {
        Unit = {
          Description = "Lan Mouse mouse and keyboard sharing daemon";
          After = [ "graphical-session.target" ];
          BindsTo = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${lib.getExe pkgs.lan-mouse} daemon";
          Restart = "on-failure";
          RestartSec = "5s";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
