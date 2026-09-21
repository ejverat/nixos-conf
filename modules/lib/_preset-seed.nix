# Shared shell body that seeds vendored slicer presets into an application's
# writable data directory. Used by both the OrcaSlicer and PrusaSlicer preset
# features, which differ only in where the tree goes.
#
# These applications write to those directories at runtime (new presets, edits,
# caches, an instance lock), so they cannot be modelled with `home.file` or
# `xdg.configFile`: store paths are read-only and the application would break the
# moment it tried to save. The presets are therefore seeded as ordinary files,
# and **only when one is missing**, so a copy the user edited in the GUI always
# wins over the vendored one. That is the same policy `_gentle-profile.nix` uses.
#
# Applying repo-side changes to a host that already has the files is deliberately
# not this body's job: that is what the preset sync script does.
#
# The body is structure-agnostic on purpose. OrcaSlicer keeps JSON presets with
# `.info` sidecars under `user/default/<kind>/`, PrusaSlicer keeps flat `.ini`
# files directly under `<kind>/`, and neither shape is assumed here: the vendored
# tree is walked recursively and recreated verbatim under `destination`.
#
# Lives under modules/lib/ with a leading underscore so import-tree skips it.
{
  homeDir,
  vendored,
  destination,
}: ''
  src="${vendored}"
  dst="${homeDir}/.config/${destination}"

  if [ ! -d "$src" ]; then
    echo "preset-seed: no vendored presets at $src, nothing to seed" >&2
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
      echo "preset-seed: seeded $seeded preset file(s) into $dst"
    fi
  fi
''
