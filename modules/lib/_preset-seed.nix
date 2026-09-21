# Shared shell body that seeds a source tree into a writable destination, used
# by the slicer preset features to place the presets their applications expect.
#
# Why a seed and not `home.file`: these destinations are written to at runtime by
# the applications (new presets, edits, caches, an instance lock), and store paths
# are read-only, so linking them would break the application the moment it tried
# to save. Each file is therefore copied **only when it is missing**, so a copy
# the user edited in the GUI always wins over the seeded one. That is the same
# policy `_gentle-profile.nix` uses.
#
# Read-only inputs are a different case and do not belong here: the PrusaSlicer
# bed assets are linked with `home.file` instead, because the application only
# ever reads them and a link cannot drift.
#
# Applying repo-side changes to a host that already has the files is deliberately
# not this body's job: that is what the preset sync script is for.
#
# The body is structure-agnostic: the source tree is walked recursively and
# recreated verbatim under `dst`. OrcaSlicer keeps JSON presets with `.info`
# sidecars under `user/default/<kind>/` and PrusaSlicer keeps flat `.ini` files
# directly under `<kind>/`; neither shape is assumed.
#
# Lives under modules/lib/ with a leading underscore so import-tree skips it.
{
  src,
  dst,
}: ''
  src=${builtins.toJSON src}
  dst=${builtins.toJSON dst}

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
''
