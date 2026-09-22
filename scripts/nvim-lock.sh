#!/usr/bin/env bash
#
# nvim-lock.sh — keep the tracked Neovim plugin lockfile in sync with the one
# lazy.nvim writes at runtime.
#
# lazy.nvim always writes stdpath("config")/lazy-lock.json, which is
# ~/.config/nvim/lazy-lock.json and is NOT part of this repository: the config
# directory is materialized read-only from the Nix store at
# ~/.dotfiles/config/nvim (see modules/features/dotfiles.nix). The tracked copy
# in dotfiles/config/nvim/lazy-lock.json is therefore the pinned snapshot:
#
#   sync   runtime -> repo    after `:Lazy update`, so the repo pins what runs
#   seed   repo -> runtime    on a fresh machine, before `:Lazy restore`
#   check  compare both copies and exit 1 on drift (sorted, order-independent)
#
# Usage:
#   ./scripts/nvim-lock.sh check     # report only, change nothing
#   ./scripts/nvim-lock.sh sync      # capture the current runtime pins
#   ./scripts/nvim-lock.sh seed      # restore the tracked pins before `:Lazy restore`

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tracked="$repo_root/dotfiles/config/nvim/lazy-lock.json"
runtime="$HOME/.config/nvim/lazy-lock.json"

count_entries() {
  grep -c '"branch"' "$1" 2>/dev/null || echo 0
}

usage() {
  sed -n '3,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

case "${1:-}" in
  sync)
    if [[ ! -f "$runtime" ]]; then
      echo "no runtime lockfile at $runtime (start Neovim once)" >&2
      exit 1
    fi
    cp "$runtime" "$tracked"
    echo "synced $(count_entries "$tracked") entries into $tracked"
    ;;
  seed)
    if [[ ! -f "$tracked" ]]; then
      echo "no tracked lockfile at $tracked" >&2
      exit 1
    fi
    mkdir -p "$(dirname "$runtime")"
    if [[ -f "$runtime" ]] && ! diff -q <(sort "$tracked") <(sort "$runtime") >/dev/null; then
      cp "$runtime" "$runtime.bak"
      echo "backed up the previous runtime lockfile to $runtime.bak"
    fi
    cp "$tracked" "$runtime"
    echo "seeded $runtime with $(count_entries "$tracked") entries; run :Lazy restore in Neovim"
    ;;
  check)
    if [[ ! -f "$runtime" ]]; then
      echo "drift: no runtime lockfile at $runtime" >&2
      exit 1
    fi
    if diff -q <(sort "$tracked") <(sort "$runtime") >/dev/null; then
      echo "in sync ($(count_entries "$tracked") entries)"
      exit 0
    fi
    echo "drift: tracked $(count_entries "$tracked") entries vs runtime $(count_entries "$runtime")" >&2
    diff <(sort "$tracked") <(sort "$runtime") | head -20 >&2
    exit 1
    ;;
  *)
    usage
    exit 2
    ;;
esac
