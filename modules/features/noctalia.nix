{ self, inputs, ... }: {
	perSystem = { pkgs, ... }: {
		packages.myNoctalia = inputs.wrapper-modules.wrappers.noctalia-shell.wrap {
			inherit pkgs;
		};

		packages.sync-noctalia = pkgs.writeShellScriptBin "sync-noctalia" ''
			exec ${pkgs.python3}/bin/python3 -c "
import json, os

cfg_path = 'modules/features/noctalia.json'
if not os.path.isfile(cfg_path):
	print('Error: run this from the nixos-conf repo root')
	exit(1)

settings_path = os.path.expanduser('~/.config/noctalia/settings.json')

with open(cfg_path) as f:
	cfg = json.load(f)
with open(settings_path) as f:
	cfg['settings'] = json.load(f)
with open(cfg_path, 'w') as f:
	json.dump(cfg, f, indent=2)
print('noctalia.json synced from runtime settings')
"
		'';
	};
}
