#!/usr/bin/env bash
# bootstrap.sh — Root orchestrator for Nix-on-Debian setup
# Calls each step in order. Each step is independently runnable.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# ── Validate environment ──
validate_env() {
    heading "Validating environment"

    if ! is_debian; then
        warn "This doesn't appear to be a Debian system"
    fi

    if [ "$EUID" -eq 0 ]; then
        warn "Running as root — this script is designed for a normal user with sudo"
    fi

    msg "Repository: $REPO_DIR"
    msg "User: $(whoami)"
}

# ── Menu ──
show_menu() {
    echo ""
    echo -e "${BOLD}Available steps:${NC}"
    echo "  all       — Run every step in order"
    echo "  1         — System prerequisites (apt packages, firmware)"
    echo "  2         — Install / validate Nix"
    echo "  3         — Configure Nix (flakes, trusted users)"
    echo "  4         — Install app bundle via Nix"
    echo "  5         — System services (apt + systemd)"
    echo "  6         — Kernel modules"
    echo "  7         — Shell + dotfiles"
    echo "  8         — Desktop config (niri, Noctalia)"
    echo "  q         — Quit"
    echo ""
}

run_selected() {
    case "$1" in
        all|ALL)
            # shellcheck disable=SC1091
            for step in "$SCRIPT_DIR"/steps/0*.sh; do
                local name; name=$(basename "$step" .sh)
                run_step "$name" "$step"
            done
            ;;
        1) run_step "prereqs"        "$SCRIPT_DIR/steps/01-prereqs.sh" ;;
        2) run_step "nix"            "$SCRIPT_DIR/steps/02-nix.sh" ;;
        3) run_step "configure-nix"  "$SCRIPT_DIR/steps/03-configure-nix.sh" ;;
        4) run_step "bundle"         "$SCRIPT_DIR/steps/04-bundle.sh" ;;
        5) run_step "services"       "$SCRIPT_DIR/steps/05-services.sh" ;;
        6) run_step "kernel"         "$SCRIPT_DIR/steps/06-kernel.sh" ;;
        7) run_step "shell"          "$SCRIPT_DIR/steps/07-shell.sh" ;;
        8) run_step "desktop"        "$SCRIPT_DIR/steps/08-desktop.sh" ;;
        q|Q) echo "Done."; exit 0 ;;
        *) warn "Unknown option: $1" ;;
    esac
}

# ── Main ──
main() {
    echo ""
    echo -e "${BOLD}==============================================${NC}"
    echo -e "${BOLD}  Nix-on-Debian Bootstrap${NC}"
    echo -e "${BOLD}  gear5th / ejverat${NC}"
    echo -e "${BOLD}==============================================${NC}"

    validate_env

    if [ $# -gt 0 ]; then
        # CLI mode: bootstrap.sh <step>
        for arg in "$@"; do
            run_selected "$arg"
        done
    else
        # Interactive mode
        show_menu
        read -rp "Select steps to run: " choice
        # shellcheck disable=SC2086
        for c in $choice; do
            run_selected "$c"
        done
    fi

    echo ""
    msg "Done. See README.md for post-install steps."
}

main "$@"
