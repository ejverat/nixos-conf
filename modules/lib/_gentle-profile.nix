# Shared shell body that seeds the vendored `gentle-profile` script into
# ~/.pi/gentle-ai (only when missing, so a runtime-provided copy always wins)
# and links it at ~/.local/bin/gentle-profile.
#
# Used by the NixOS activation (root: pass `owner` for the chowns) and the
# home-manager activation (user: `owner = null`).
#
# Lives under modules/lib/ with a leading underscore so import-tree skips it.
{
  lib,
  homeDir,
  vendored,
  owner ? null,
}: let
  chown = flags: path:
    lib.optionalString (owner != null)
    "chown ${lib.optionalString (flags != "") "${flags} "}${owner} ${path} 2>/dev/null || true";
in ''
  src="${homeDir}/.pi/gentle-ai/gentle-profile"
  dst="${homeDir}/.local/bin/gentle-profile"
  vendored="${vendored}"

  if [ ! -f "$src" ]; then
    mkdir -p "$(dirname "$src")"
    install -m 0755 "$vendored" "$src"
    ${chown "" "\"$src\""}
    echo "gentle-profile: seeded $src from the vendored copy"
  else
    chmod u+x "$src" 2>/dev/null || true
  fi

  mkdir -p "$(dirname "$dst")"
  ln -sfn "$src" "$dst"
  ${chown "-h" "\"$dst\""}
  ${chown "" "\"$(dirname \"$dst\")\""}
''
