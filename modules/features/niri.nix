{ self, inputs, ... }:
{

	flake.nixosModules.niri = { config, pkgs, lib, ... }: {
		programs.niri = {
			enable = true;
			package = self.packages.${pkgs.stdenv.hostPlatform.system}.myNiri;
		};
	};

	# Portable user layer (non-NixOS hosts): install the same config-baked niri
	# package into the user profile. No display manager on Debian can load
	# nix-store wayland sessions, so the portable zsh wrapper starts it from
	# tty1 (see myZshPortable). GPU/DRM vs the Debian kernel drivers is the
	# early validation area on gear5th.
	flake.homeModules.niri = { pkgs, flakeSelf, ... }: {
		home.packages = [
			flakeSelf.packages.${pkgs.stdenv.hostPlatform.system}.myNiri
			# The wrapper config enables xwayland-satellite, which execs
			# `Xwayland` from PATH. On NixOS the system profile provides it;
			# on a standalone session there is no system profile, so bring it
			# explicitly or X11 apps (wezterm with enable_wayland=false)
			# silently get no Xwayland.
			pkgs.xwayland
			# GL drivers for the /run/opengl-driver tree that nixpkgs' libgbm
			# and libglvnd look for (scripts/fix-opengl-driver.sh points the
			# tree here). On NixOS this comes from the system profile; in the
			# profile it is also the GC root that keeps the drivers alive.
			pkgs.mesa
		];

		# Display-manager path (scripts/install-niri-session.sh registers the
		# GDM session): niri-session starts the systemd user unit `niri.service`
		# and waits for it. The unit ships with the package (ExecStart points at
		# the config-baked wrapper) and must live in the user manager's search
		# path, which ~/.config/systemd/user is.
		xdg.configFile."systemd/user/niri.service".source =
			"${flakeSelf.packages.${pkgs.stdenv.hostPlatform.system}.myNiri}/share/systemd/user/niri.service";
		xdg.configFile."systemd/user/niri-shutdown.target".source =
			"${flakeSelf.packages.${pkgs.stdenv.hostPlatform.system}.myNiri}/share/systemd/user/niri-shutdown.target";
	};

	perSystem = { config, pkgs, lib, self', ... }: 
	let
		noctaliaCmd = lib.getExe self'.packages.myNoctalia;
		terminalCmd = lib.getExe pkgs.wezterm;
	in
	{
		# Flake-level handle on the GL drivers package the /run/opengl-driver
		# tree must point to on non-NixOS hosts. Resolving it as an output is
		# deterministic (no closure walking) and always matches the pin that
		# also built libgbm/libglvnd for this host:
		#   nix eval --raw .#packages.x86_64-linux.mesaDrivers.outPath
		packages.mesaDrivers = pkgs.mesa;

		packages.myNiri = inputs.wrapper-modules.wrappers.niri.wrap {
			inherit pkgs;
			settings = {

        prefer-no-csd = (_: {});

        spawn-at-startup = [
					noctaliaCmd
				];

        input = {

          keyboard = {
            xkb.layout = "us,latam";
            xkb.options = "grp:win_space_toggle,compose:ralt,ctrl:nocaps";
          };

          touchpad = {
            natural-scroll = (_: {});
            tap = (_: {});
          };

          mouse = {
            accel-profile = "flat";
          };

        };

        layout = {
          gaps = 4;

          focus-ring = {
            width = 2;
          };
        };

        workspaces = let
          settings = {layout.gaps = 5;};
        in {
          "w0" = settings;
          "w1" = settings;
          "w2" = settings;
          "w3" = settings;
          "w4" = settings;
          "w5" = settings;
          "w6" = settings;
          "w7" = settings;
          "w8" = settings;
          "w9" = settings;
        };

        binds = {
          "Mod+Shift+Slash".show-hotkey-overlay = (_: {});
          "Mod+D".spawn-sh = "${noctaliaCmd} ipc call launcher toggle";
          "Super+Alt+L".spawn-sh = "${noctaliaCmd} ipc call lockScreen lock";
          "Mod+Shift+X".spawn-sh = "${noctaliaCmd} ipc call sessionMenu toggle";

          "Mod+Return".spawn-sh = terminalCmd;
          "Mod+Q".close-window = {};
          "Mod+F".maximize-column = {};
          "Mod+G".fullscreen-window = {};
          "Mod+Shift+F".toggle-window-floating = {};
          "Mod+C".center-column = {};

          "Mod+H".focus-column-left = {};
          "Mod+L".focus-column-right = {};
          "Mod+K".focus-window-up = {};
          "Mod+J".focus-window-down = {};

          "Mod+Left".focus-column-left = {};
          "Mod+Right".focus-column-right = {};
          "Mod+Up".focus-window-up = {};
          "Mod+Down".focus-window-down = {};

          "Mod+Shift+H".move-column-left = {};
          "Mod+Shift+L".move-column-right = {};
          "Mod+Shift+K".move-window-up = {};
          "Mod+Shift+J".move-window-down = {};

          "Mod+1".focus-workspace = "w0";
          "Mod+2".focus-workspace = "w1";
          "Mod+3".focus-workspace = "w2";
          "Mod+4".focus-workspace = "w3";
          "Mod+5".focus-workspace = "w4";
          "Mod+6".focus-workspace = "w5";
          "Mod+7".focus-workspace = "w6";
          "Mod+8".focus-workspace = "w7";
          "Mod+9".focus-workspace = "w8";
          "Mod+0".focus-workspace = "w9";

          "Mod+Shift+1".move-column-to-workspace = "w0";
          "Mod+Shift+2".move-column-to-workspace = "w1";
          "Mod+Shift+3".move-column-to-workspace = "w2";
          "Mod+Shift+4".move-column-to-workspace = "w3";
          "Mod+Shift+5".move-column-to-workspace = "w4";
          "Mod+Shift+6".move-column-to-workspace = "w5";
          "Mod+Shift+7".move-column-to-workspace = "w6";
          "Mod+Shift+8".move-column-to-workspace = "w7";
          "Mod+Shift+9".move-column-to-workspace = "w8";
          "Mod+Shift+0".move-column-to-workspace = "w9";

# "Mod+V".spawn-sh = ''${config.pkgs.alsa-utils}/bin/amixer sset Capture toggle'';
          "XF86AudioRaiseVolume".spawn-sh = "wpctl set-volume -l 1.4 @DEFAULT_AUDIO_SINK@ 5%+";
          "XF86AudioLowerVolume".spawn-sh = "wpctl set-volume -l 1.4 @DEFAULT_AUDIO_SINK@ 5%-";

          "Mod+Ctrl+H".set-column-width = "-5%";
          "Mod+Ctrl+L".set-column-width = "+5%";
          "Mod+Ctrl+J".set-window-height = "-5%";
          "Mod+Ctrl+K".set-window-height = "+5%";

          "Mod+WheelScrollDown".focus-column-left = {};
          "Mod+WheelScrollUp".focus-column-right = {};
          "Mod+Ctrl+WheelScrollDown".focus-workspace-down = {};
          "Mod+Ctrl+WheelScrollUp".focus-workspace-up = {};
        };

        xwayland-satellite.path = lib.getExe pkgs.xwayland-satellite;
      };
    };
  };

}
