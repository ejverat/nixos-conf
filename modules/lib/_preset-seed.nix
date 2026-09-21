# Shared shell body that seeds source trees into writable destinations, used by
# the slicer preset features to place things the applications expect to find on
# disk.
#
# Why a seed and not `home.file`: these destinations are written to at runtime by
# the applications (new presets, edits, caches, an instance lock), and store paths
# are read-only, so linking them would break the application the moment it tried
# to save. Each file is therefore copied **only when it is missing**, so a copy
# the user edited in the GUI always wins over the seeded one. That is the same
# policy `_gentle-profile.nix` uses.
#
# Applying repo-side changes to a host that already has the files is deliberately
# not this body's job: that is what the preset sync script is for.
#
# `seeds` is a list of `{ src, dst }` pairs, and the body is structure-agnostic:
# the source tree is walked recursively and recreated verbatim under `dst`.
# OrcaSlicer keeps JSON presets with `.info` sidecars under `user/default/<kind>/`,
# PrusaSlicer keeps flat `.ini` files directly under `<kind>/`, and a pair can
# also target a path outside the config directory when an application references
# an asset by absolute path. None of those shapes is assumed here.
#
# Lives under modules/lib/ with a leading underscore so import-tree skips it.
{
  lib,
  seeds,
}:
lib.concatMapStrings (seed: ''
  src=${lib.escapeShellArg seed.src}
  dst=${lib.escapeShellArg seed.dst}

  if [ ! -d "$src" ]; then
    echo "preset-seed: no source tree at $src, nothing to seed" >&2
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
      echo "preset-seed: seeded $seeded file(s) into $dst"
    fi
  fi
'') seeds
