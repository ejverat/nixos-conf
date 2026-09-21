# Shared sops wrapper generator for editing/re-encrypting secrets/secrets.yaml.
#
# The two hosts resolve the age identity differently: NixOS converts the root
# SSH host key in memory (with a sudo fallback), while the standalone host uses
# the user's own SSH key. That difference is injected as an `identity` shell
# fragment which must write the age identity to "$tmp". Everything else (temp
# file handling, shredding, the sops invocation) is shared.
#
# Lives under modules/lib/ with a leading underscore so import-tree skips it.
{
  pkgs,
  name,
  identity,
  extra ? "",
}: pkgs.writeShellApplication {
  inherit name;
  runtimeInputs = [pkgs.sops pkgs.coreutils pkgs.ssh-to-age];
  text = ''
    set -euo pipefail

    target="''${1:-secrets/secrets.yaml}"

    tmp="$(mktemp)"
    chmod 600 "$tmp"
    trap 'rm -f "$tmp"' EXIT

    ${identity}

    SOPS_AGE_KEY_FILE="$tmp" sops ${extra} "$target"
  '';
}
