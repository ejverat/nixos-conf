# Shared shell body that seeds the vendored OrcaSlicer user presets into the
# application's writable data directory.
#
# OrcaSlicer writes to that directory at runtime (new presets, edits, caches,
# an instance lock), so it cannot be modelled with `home.file` or
# `xdg.configFile`: store paths are read-only and the application would break the
# moment it tried to save. The presets are therefore seeded as ordinary files,
# and **only when one is missing**, so a copy the user edited in the GUI always
# wins over the vendored one. That is the same policy `_gentle-profile.nix` uses.
#
# Applying repo-side changes to a host that already has the files is deliberately
# not this body's job: that is `scripts/orca-presets.sh pull`.
#
# Lives under modules/lib/ with a leading underscore so import-tree skips it.
{
  homeDir,
  vendored,
}: ''
  src="${vendored}"
  dst="${homeDir}/.config/OrcaSlicer/user/default"

  if [ ! -d "$src" ]; then
    echo "orca-presets: no vendored presets at $src, nothing to seed" >&2
  else
    mkdir -p "$dst"
    seeded=0
    while IFS= read -r -d "" rel; do
      target="$dst/$rel"
      if [ -e "$target" ]; then
        continue
      fi
      mkdir -p "$(dirname "$target")"
      install -m 0644 "$src/$rel" "$target"
      seeded=$((seeded + 1))
    done < <(find "$src" -type f -printf '%P\0' 2>/dev/null)

    if [ "$seeded" -gt 0 ]; then
      echo "orca-presets: seeded $seeded preset file(s) into $dst"
    fi
  fi
''
