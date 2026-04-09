{ self, inputs, ... }:
{

	flake.nixosModules.niri = { pkgs, lib, ... }: {
		programs.niri = {
			enable = true;
			package = self.packages.${pkgs.stdenv.hostPlatform.system}.myNiri;
		};
	};

	perSystem = { pkgs, lib, self', ... }: 
	let
		noctaliaCmd = lib.getExe self'.packages.myNoctalia;
	in
	{
		packages.myNiri = inputs.wrapper-modules.wrappers.niri.wrap {
			inherit pkgs;
			settings = {
				spawn-at-startup = [
					noctaliaCmd
				];
				input.keyboard = {
					xkb.layout = "us,latam";
				};

				layout.gaps = 5;

				binds = {
					"Mod+S".spawn-sh = "${noctaliaCmd} ipc call launcher toggle";
					"Mod+Return".spawn-sh = lib.getExe pkgs.kitty;
					"Mod+Q".close-window = (_: {});
				};
			};
		};
	};

}
