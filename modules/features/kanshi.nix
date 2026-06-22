{ ... }: {
	flake.nixosModules.kanshi = { pkgs, lib, ... }: {
		environment.systemPackages = [ pkgs.kanshi ];

		environment.etc."kanshi/config".text = ''
			profile home {
				output HDMI-A-1 enable scale 1.0 mode 1920x1080@60.000Hz position 0,0
				output eDP-1 enable scale 1.0 mode 1366x768@60.003Hz position 0,1080
			}

			profile docked {
				output HDMI-A-1 enable scale 1.0 mode 1920x1080@60.000Hz position 0,0
			}

			profile laptop {
				output eDP-1 enable scale 1.0 mode 1366x768@60.003Hz position 0,0
			}
		'';

		systemd.user.services.kanshi = {
			description = "Kanshi output management daemon";
			wantedBy = [ "default.target" ];
			serviceConfig = {
				ExecStart = "${lib.getExe pkgs.kanshi} -c /etc/kanshi/config";
				Restart = "on-failure";
				RestartSec = "5s";
			};
		};
	};
}
