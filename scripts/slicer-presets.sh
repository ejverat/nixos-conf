#!/usr/bin/env bash
#
# slicer-presets.sh — keep vendored slicer presets and the live application
# directories in sync.
#
# The seeds in modules/lib/_preset-seed.nix only copy a preset **when it is
# missing**, so a copy edited in the GUI always wins. That is the right default
# on a fresh host, but it means two things need an explicit tool:
#
#   push   capture presets you edited in the GUI back into this repository
#   pull   apply repository-side changes to a host that already has the files
#
# Usage:
#   ./scripts/slicer-presets.sh <tool> status              # read-only report
#   ./scripts/slicer-presets.sh <tool> push [--dry-run]    # live -> repo
#   ./scripts/slicer-presets.sh <tool> pull [--dry-run]    # repo -> live (backs up first)
#
#   <tool> is one of: orca, prusa
#
# Only the trees the per-tool table below names are ever touched. Everything else
# in an application's data directory is out of scope by construction: identifiers
# and window state, data the application regenerates, and caches.
#
# The preset *shape* deliberately does not appear in the logic: the vendored tree
# is walked and mirrored, so OrcaSlicer's JSON presets with `.info` sidecars under
# a nested subdirectory and PrusaSlicer's flat `.ini` files both work unchanged.
#
# Environment:
#   REPO_DIR          repository root (default: the parent of this script)
#   SLICER_DATA_DIR   override the application's config directory
#                     (default: $XDG_CONFIG_HOME/<application>)

set -euo pipefail

DRY_RUN=0
TOOL=""
ACTION=""
for arg in "$@"; do
    case "$arg" in
        status|push|pull) ACTION="$arg" ;;
        orca|prusa) TOOL="$arg" ;;
        --dry-run) DRY_RUN=1 ;;
        -h|--help) awk 'NR>1 && /^set -euo/{exit} NR>1 {sub(/^# ?/, ""); print}' "$0"; exit 0 ;;
        *) echo "[x] unknown argument: $arg" >&2; exit 2 ;;
    esac
done

[ -n "$TOOL" ] || { echo "[x] expected a tool: orca or prusa (see --help)" >&2; exit 2; }
[ -n "$ACTION" ] || { echo "[x] expected one of: status, push, pull (see --help)" >&2; exit 2; }

# Per-tool paths, the whole of what differs between applications.
#   SRC_REL  vendored tree inside this repository
#   APP      the application's directory under the config home
#   SUB      the preset subtree inside it, empty when the presets sit at the root
case "$TOOL" in
    orca)
        SRC_REL="dotfiles/orcaslicer/user-default"
        APP="OrcaSlicer"
        SUB="user/default"
        ;;
    prusa)
        SRC_REL="dotfiles/prusaslicer/presets"
        APP="PrusaSlicer"
        SUB=""
        ;;
esac

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
SRC="$REPO_DIR/$SRC_REL"
DATA_DIR="${SLICER_DATA_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/$APP}"
DEST="$DATA_DIR${SUB:+/$SUB}"

ok() { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*"; }

if [ ! -d "$SRC" ]; then
    echo "[x] no vendored presets at $SRC (run from the repo, or set REPO_DIR)" >&2
    exit 1
fi

# Relative file lists, NUL-delimited so preset names (which contain spaces and
# '@') survive intact.
repo_files() { find "$SRC" -type f -printf '%P\0'; }
live_files() { [ -d "$DEST" ] && find "$DEST" -type f -printf '%P\0' || true; }

# Does the live tree contain anything at all? Guards push/pull against running
# against an empty or missing directory.
have_live() { [ -d "$DEST" ] && [ -n "$(find "$DEST" -type f -print -quit 2>/dev/null)" ]; }

case "$ACTION" in
status)
    same=0 differs=0 only_repo=0 only_live=0
    while IFS= read -r -d "" rel; do
        if [ ! -e "$DEST/$rel" ]; then
            warn "missing live   : $rel"
            only_repo=$((only_repo + 1))
        elif cmp -s "$SRC/$rel" "$DEST/$rel"; then
            same=$((same + 1))
        else
            warn "differs        : $rel"
            differs=$((differs + 1))
        fi
    done < <(repo_files)

    while IFS= read -r -d "" rel; do
        if [ ! -e "$SRC/$rel" ]; then
            warn "only live      : $rel"
            only_live=$((only_live + 1))
        fi
    done < <(live_files)

    echo
    ok "tool: $TOOL"
    ok "repo: $SRC"
    ok "live: $DEST"
    echo
    ok "up to date: $same"
    [ "$differs" -gt 0 ] && warn "differ: $differs (push to capture, pull to apply)"
    [ "$only_repo" -gt 0 ] && warn "only in repo: $only_repo (pull to install)"
    [ "$only_live" -gt 0 ] && warn "only live: $only_live (push to capture)"
    exit 0
    ;;

push)
    have_live || { echo "[x] no live presets at $DEST, nothing to capture" >&2; exit 1; }
    copied=0
    while IFS= read -r -d "" rel; do
        if [ -e "$SRC/$rel" ] && cmp -s "$SRC/$rel" "$DEST/$rel"; then
            continue
        fi
        if [ "$DRY_RUN" -eq 1 ]; then
            warn "would capture  : $rel"
        else
            mkdir -p "$(dirname "$SRC/$rel")"
            install -m 0644 "$DEST/$rel" "$SRC/$rel"
            ok "captured       : $rel"
        fi
        copied=$((copied + 1))
    done < <(live_files)

    echo
    if [ "$copied" -eq 0 ]; then
        ok "nothing to capture; the repository already matches the live presets"
    elif [ "$DRY_RUN" -eq 1 ]; then
        warn "$copied file(s) would be captured into $SRC"
    else
        ok "captured $copied file(s) into $SRC"
        echo "    review with: git -C $REPO_DIR diff -- $SRC_REL"
    fi
    exit 0
    ;;

pull)
    changed=0
    while IFS= read -r -d "" rel; do
        if [ -e "$DEST/$rel" ] && cmp -s "$SRC/$rel" "$DEST/$rel"; then
            continue
        fi
        if [ "$DRY_RUN" -eq 1 ]; then
            if [ -e "$DEST/$rel" ]; then warn "would overwrite: $rel"; else warn "would install  : $rel"; fi
        fi
        changed=$((changed + 1))
    done < <(repo_files)

    if [ "$changed" -eq 0 ]; then
        echo
        ok "nothing to apply; the live presets already match the repository"
        exit 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        echo
        warn "$changed file(s) would be applied to $DEST (dry run, nothing written)"
        exit 0
    fi

    # Back up the whole live tree once before touching anything.
    #
    # The backup lives under the state directory, **not** inside the application's
    # config directory, and that placement is load-bearing: PrusaSlicer keeps its
    # presets at the root of its config directory, so `DEST` and `DATA_DIR` are the
    # same path there and an in-place backup would be copied into itself. Keeping
    # it outside both applications' directories removes that hazard for every tool
    # rather than special-casing one, and the applications never see it either.
    if have_live; then
        backup="${XDG_STATE_HOME:-$HOME/.local/state}/slicer-presets-backups/$TOOL/$(date +%Y%m%d%H%M%S)"
        mkdir -p "$backup"
        cp -a "$DEST/." "$backup/"
        ok "backed up the live presets to $backup"
    fi

    while IFS= read -r -d "" rel; do
        if [ -e "$DEST/$rel" ] && cmp -s "$SRC/$rel" "$DEST/$rel"; then
            continue
        fi
        mkdir -p "$(dirname "$DEST/$rel")"
        install -m 0644 "$SRC/$rel" "$DEST/$rel"
        ok "applied        : $rel"
    done < <(repo_files)

    echo
    ok "applied $changed file(s) to $DEST"
    echo "    files that exist only in the live tree were left untouched (that is push's business)"
    exit 0
    ;;
esac
