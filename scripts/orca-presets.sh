#!/usr/bin/env bash
#
# orca-presets.sh — keep the vendored OrcaSlicer user presets and the live
# application data directory in sync.
#
# The activation in modules/lib/_orca-presets.nix only seeds a preset **when it
# is missing**, so a copy edited in the GUI always wins. That is the right
# default on a fresh host, but it means two things need an explicit tool:
#
#   push   capture presets you edited in the GUI back into this repository
#   pull   apply repository-side changes to a host that already has the files
#
# Only the three preset subtrees are ever touched (`machine`, `process`,
# `filament`). The machine id, OrcaSlicer.conf, system/, printers/ and the
# transient directories are out of scope by construction.
#
# Usage:
#   ./scripts/orca-presets.sh status              # read-only report
#   ./scripts/orca-presets.sh push [--dry-run]    # live -> repo
#   ./scripts/orca-presets.sh pull [--dry-run]    # repo -> live (backs up first)
#
# Environment:
#   REPO_DIR        repository root (default: the parent of this script)
#   ORCA_DATA_DIR   OrcaSlicer data dir (default: $XDG_CONFIG_HOME/OrcaSlicer)

set -euo pipefail

DRY_RUN=0
ACTION=""
for arg in "$@"; do
    case "$arg" in
        status|push|pull) ACTION="$arg" ;;
        --dry-run) DRY_RUN=1 ;;
        -h|--help) awk 'NR>1 && /^set -euo/{exit} NR>1 {sub(/^# ?/, ""); print}' "$0"; exit 0 ;;
        *) echo "[x] unknown argument: $arg" >&2; exit 2 ;;
    esac
done

if [ -z "$ACTION" ]; then
    echo "[x] expected one of: status, push, pull (see --help)" >&2
    exit 2
fi

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
SRC="$REPO_DIR/dotfiles/orcaslicer/user-default"
DATA_DIR="${ORCA_DATA_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/OrcaSlicer}"
DEST="$DATA_DIR/user/default"

ok() { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*"; }

if [ ! -d "$SRC" ]; then
    echo "[x] no vendored presets at $SRC (run from the repo, or set REPO_DIR)" >&2
    exit 1
fi

# Relative file lists, NUL-delimited so the preset names (which all contain
# spaces and '@') survive intact.
repo_files() { find "$SRC" -type f -printf '%P\0'; }
live_files() { [ -d "$DEST" ] && find "$DEST" -type f -printf '%P\0' || true; }

# Does the live preset tree contain anything at all? Guards pull/push against
# running against an empty or missing data directory.
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
        echo "    review with: git -C $REPO_DIR diff -- dotfiles/orcaslicer"
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

    # Back up the whole live preset tree once, outside user/, before touching it.
    # The name follows the application's own user_backup-* convention.
    if have_live; then
        backup="$DATA_DIR/user_backup-presets.$(date +%Y%m%d%H%M%S)"
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
