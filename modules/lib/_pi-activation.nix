# Shared shell body that ensures ~/.pi/agent/settings.json exists and merges a
# Nix-built pi package into it (additively, because pi rewrites that file at
# runtime). Used by the NixOS activation (root: pass `owner` so the created
# paths are chowned) and the home-manager activation (user: `owner = null`).
#
# The generated text is deliberately close to the previous per-variant copies;
# the only change is that the chown runs right after each creation instead of
# being spelled out inline.
#
# Lives under modules/lib/ with a leading underscore so import-tree skips it.
{
  lib,
  pkgs,
  homeDir,
  package,
  pkgRegex,
  owner ? null,
}: let
  piSettings = import ./_pi-settings.nix;
  chown = flags: path:
    lib.optionalString (owner != null)
    "chown ${lib.optionalString (flags != "") "${flags} "}${owner} ${path}";
in ''
  agentDir="${homeDir}/.pi/agent"
  settings="$agentDir/settings.json"

  if [ ! -d "$agentDir" ]; then
    mkdir -p "$agentDir"
    ${chown "-R" "\"${homeDir}/.pi\""}
  fi

  if [ ! -f "$settings" ]; then
    echo '{}' > "$settings"
    ${chown "" "\"$settings\""}
  fi

  ${piSettings {inherit pkgs package pkgRegex;}}
''
