# Shared shell fragment that merges a Nix-built pi package into the
# user-writable ~/.pi/agent/settings.json.
#
# pi owns that file at runtime (it installs and removes packages itself), so
# neither the NixOS nor the home-manager variant can manage it declaratively:
# both merge additively instead. This lives in modules/lib/_pi-settings.nix
# because import-tree skips paths containing "/_" — without the underscore it
# would be evaluated as a flake-parts module and fail.
#
# The caller defines a shell variable `settings` (absolute path to the settings
# file) in the surrounding script, and passes the package store path plus the
# prune regex. The regex must tolerate the `-<version>` suffix of a store path,
# otherwise stale versions accumulate and pi aborts on duplicate tool names.
{pkgs, package, pkgRegex}: ''
  tmp=$(${pkgs.coreutils}/bin/mktemp)
  if ${pkgs.jq}/bin/jq --arg pkg "${package}" '
    .packages = (
      ((.packages // [])
        | map(select(
            ((type == "string" and test("${pkgRegex}"))
             or (type == "object" and ((.source? // "") | test("${pkgRegex}"))))
            | not)))
      + [$pkg] | unique)
  ' "$settings" > "$tmp"; then
    ${pkgs.coreutils}/bin/cat "$tmp" > "$settings"
  else
    echo "pi: could not merge ${package} into $settings; leaving it unchanged" >&2
  fi
  ${pkgs.coreutils}/bin/rm -f "$tmp"
''
