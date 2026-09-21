{ self, inputs, ... }:
{

	flake.nixosModules.niri = { config, pkgs, lib, ... }: {
		programs.niri = {
			enable = true;
			package = self.packages.${pkgs.stdenv.hostPlatform.system}.myNiri;
		};
		# noctalia's BrightnessService shells out to brightnessctl for the
		# internal panel, and the XF86MonBrightness binds go through noctalia.
		environment.systemPackages = [ pkgs.brightnessctl ];
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
			# noctalia's BrightnessService shells out to brightnessctl for the
			# internal panel, and the XF86MonBrightness binds go through noctalia.
			pkgs.brightnessctl
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
		# Every panel, launcher and OSD lives behind noctalia's IPC, so the binds
		# below stay one line each and share the exact same executable path.
		noctaliaIpc = call: "${noctaliaCmd} ipc call ${call}";
		# niri's hotkey overlay prints the raw command of a spawn bind, and every
		# command here is an absolute store path. spawnSh attaches the title the
		# overlay should show instead of the path.
		spawnSh = title: cmd: (_: {
			props.hotkey-overlay-title = title;
			content."spawn-sh" = cmd;
		});
		# Same, for the binds that must keep working on the lock screen. A null
		# title hides the bind from the hotkey overlay instead of titling it.
		spawnShLocked = title: cmd: (_: {
			props = {
				hotkey-overlay-title = title;
				allow-when-locked = true;
			};
			content."spawn-sh" = cmd;
		});
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
          # Shell: launcher, panels and the on-screen displays.
          "Mod+Shift+Slash".show-hotkey-overlay = (_: {});
          "Mod+D" = spawnSh "Run an application" (noctaliaIpc "launcher toggle");
          "Mod+B" = spawnSh "Clipboard history" (noctaliaIpc "launcher clipboard");
          "Mod+A" = spawnSh "Control center" (noctaliaIpc "controlCenter toggle");
          "Mod+N" = spawnSh "Notification history" (noctaliaIpc "notifications toggleHistory");
          "Mod+Shift+N" = spawnSh "Toggle do not disturb" (noctaliaIpc "notifications toggleDND");
          "Mod+Shift+B" = spawnSh "Toggle the bar" (noctaliaIpc "bar toggle");
          "Mod+Shift+D" = spawnSh "Toggle dark mode" (noctaliaIpc "darkMode toggle");
          "Mod+Shift+T" = spawnSh "Toggle the idle inhibitor" (noctaliaIpc "idleInhibitor toggle");
          "Mod+Shift+M" = spawnSh "Media player panel" (noctaliaIpc "media toggle");
          "Mod+Alt+B" = spawnSh "Bluetooth panel" (noctaliaIpc "bluetooth togglePanel");
          "Mod+Alt+N" = spawnSh "Network panel" (noctaliaIpc "network togglePanel");
          "Mod+Alt+C" = spawnSh "Calendar" (noctaliaIpc "calendar toggle");

          # Session: lock, log out, monitors and the shortcut inhibitor.
          "Super+Alt+L" = spawnSh "Lock the screen" (noctaliaIpc "lockScreen lock");
          "Mod+Shift+X" = spawnSh "Session menu" (noctaliaIpc "sessionMenu toggle");
          "Mod+Shift+E".quit = (_: {});
          "Ctrl+Alt+Delete".quit = (_: {});
          "Mod+Shift+P".power-off-monitors = (_: {});
          "Mod+Escape" = _: {
            # Keep working while a client inhibits shortcuts (games, VMs).
            props.allow-inhibiting = false;
            content.toggle-keyboard-shortcuts-inhibit = (_: {});
          };

          # Capture: niri's region UI plus noctalia's screen toolkit.
          "Print".screenshot = (_: {});
          "Ctrl+Print".screenshot-screen = (_: {});
          "Alt+Print".screenshot-window = (_: {});
          "Mod+Shift+S" = spawnSh "Screenshot and annotation tools" (noctaliaIpc "plugin:screen-toolkit toggle");

          # Accessibility: screen reader, usable from the lock screen.
          "Super+Alt+S" = spawnShLocked "Toggle the screen reader: orca" "pkill orca || exec orca";

          "Mod+Return" = spawnSh "Open a terminal: wezterm" terminalCmd;

          # Windows: sizing, tiling and floating.
          "Mod+Q".close-window = {};
          "Mod+F".maximize-column = {};
          "Mod+M".maximize-window-to-edges = {};
          "Mod+Ctrl+F".expand-column-to-available-width = {};
          "Mod+G".fullscreen-window = {};
          "Mod+Shift+G".toggle-windowed-fullscreen = {};
          "Mod+C".center-column = {};
          "Mod+Ctrl+C".center-visible-columns = {};
          "Mod+W".toggle-column-tabbed-display = {};

          # Floating: Mod+V is niri's default, Mod+Shift+F stays as the
          # previous alias so the old muscle memory keeps working.
          "Mod+V".toggle-window-floating = {};
          "Mod+Shift+F".toggle-window-floating = {};
          "Mod+Shift+V".switch-focus-between-floating-and-tiling = {};

          # Column surgery: consume a window into the column, expel it out.
          "Mod+BracketLeft".consume-or-expel-window-left = {};
          "Mod+BracketRight".consume-or-expel-window-right = {};
          "Mod+Comma".consume-window-into-column = {};
          "Mod+Period".expel-window-from-column = {};

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

          "Mod+Home".focus-column-first = {};
          "Mod+End".focus-column-last = {};
          "Mod+Ctrl+Home".move-column-to-first = {};
          "Mod+Ctrl+End".move-column-to-last = {};

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

          # Workspaces beyond the number keys: the wheel used to be the only
          # way to change workspace, and nothing could move a column there.
          "Mod+Tab".focus-workspace-previous = (_: {});
          "Mod+Grave".focus-window-previous = (_: {});
          "Mod+Ctrl+U".move-column-to-workspace-down = (_: {});
          "Mod+Ctrl+I".move-column-to-workspace-up = (_: {});
          "Mod+Shift+U".move-workspace-down = (_: {});
          "Mod+Shift+I".move-workspace-up = (_: {});
          "Mod+Ctrl+Shift+U".move-window-to-workspace-down = (_: {});
          "Mod+Ctrl+Shift+I".move-window-to-workspace-up = (_: {});

          # Overview: the zoomed-out workspace view, also reachable from the
          # touchpad gesture and the top-left hot corner.
          "Mod+O" = _: {
            props.repeat = false;
            content.toggle-overview = (_: {});
          };

          # Monitors. kanshi drives the two-output profiles, so these need
          # explicit keys; Mod+Shift+HLJK and Mod+Alt+L are already taken by
          # move-window and the lock screen.
          "Mod+Alt+Left".focus-monitor-left = (_: {});
          "Mod+Alt+Right".focus-monitor-right = (_: {});
          "Mod+Alt+Up".focus-monitor-up = (_: {});
          "Mod+Alt+Down".focus-monitor-down = (_: {});
          "Mod+Alt+Shift+Left".move-column-to-monitor-left = (_: {});
          "Mod+Alt+Shift+Right".move-column-to-monitor-right = (_: {});
          "Mod+Alt+Shift+Up".move-column-to-monitor-up = (_: {});
          "Mod+Alt+Shift+Down".move-column-to-monitor-down = (_: {});
          "Mod+Alt+Comma".move-workspace-to-monitor-previous = (_: {});
          "Mod+Alt+Period".move-workspace-to-monitor-next = (_: {});

          # Media keys. Audio stays on wpctl so the -l 1.4 sink cap survives;
          # the transport keys use noctalia's MPRIS service, which needs no
          # external player binary. All of them must work while locked.
          # A null hotkey-overlay-title keeps them out of the overlay: the keys
          # are printed on the keyboard, and the overlay is a content-sized,
          # unscrollable dialog (10 rows is the difference between fitting and
          # being cut off on the 768px laptop panel).
          "XF86AudioRaiseVolume" = spawnShLocked null "wpctl set-volume -l 1.4 @DEFAULT_AUDIO_SINK@ 5%+";
          "XF86AudioLowerVolume" = spawnShLocked null "wpctl set-volume -l 1.4 @DEFAULT_AUDIO_SINK@ 5%-";
          "XF86AudioMute" = spawnShLocked null "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
          "XF86AudioMicMute" = spawnShLocked null "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
          "XF86AudioPlay" = spawnShLocked null (noctaliaIpc "media playPause");
          "XF86AudioStop" = spawnShLocked null (noctaliaIpc "media stop");
          "XF86AudioPrev" = spawnShLocked null (noctaliaIpc "media previous");
          "XF86AudioNext" = spawnShLocked null (noctaliaIpc "media next");

          # Brightness goes through noctalia for the on-screen display, which
          # makes brightnessctl a dependency of this config (see the packages
          # in both host layers).
          "XF86MonBrightnessUp" = spawnShLocked null (noctaliaIpc "brightness increase");
          "XF86MonBrightnessDown" = spawnShLocked null (noctaliaIpc "brightness decrease");

          # Sizing: 5% steps on the familiar keys, 10% steps on niri's defaults.
          "Mod+Ctrl+H".set-column-width = "-5%";
          "Mod+Ctrl+L".set-column-width = "+5%";
          "Mod+Ctrl+J".set-window-height = "-5%";
          "Mod+Ctrl+K".set-window-height = "+5%";
          "Mod+Minus".set-column-width = "-10%";
          "Mod+Equal".set-column-width = "+10%";
          "Mod+Shift+Minus".set-window-height = "-10%";
          "Mod+Shift+Equal".set-window-height = "+10%";
          "Mod+R".switch-preset-column-width = {};
          "Mod+Shift+R".switch-preset-column-width-back = {};
          "Mod+Ctrl+Shift+R".switch-preset-window-height = {};
          "Mod+Ctrl+R".reset-window-height = {};

          # Wheel: niri's default cooldown keeps one fast scroll from
          # jumping several columns or workspaces.
          "Mod+WheelScrollDown" = _: {
            props.cooldown-ms = 150;
            content.focus-column-left = (_: {});
          };
          "Mod+WheelScrollUp" = _: {
            props.cooldown-ms = 150;
            content.focus-column-right = (_: {});
          };
          "Mod+Ctrl+WheelScrollDown" = _: {
            props.cooldown-ms = 150;
            content.focus-workspace-down = (_: {});
          };
          "Mod+Ctrl+WheelScrollUp" = _: {
            props.cooldown-ms = 150;
            content.focus-workspace-up = (_: {});
          };
        };

        xwayland-satellite.path = lib.getExe pkgs.xwayland-satellite;
      };
    };
  };

}
