# shellcheck shell=bash
# common.sh — Shared utilities for bootstrap steps
# Source this at the top of every step script.

# ── Colors ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ── Logging ──
msg()  { echo -e "  ${GREEN}✓${NC} $1"; }
info() { echo -e "  ${BLUE}→${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
err()  { echo -e "  ${RED}✗${NC} $1"; }
fail() { err "$1"; exit 1; }
heading() {
    echo ""
    echo -e "${BOLD}── $1 ──${NC}"
}

# ── Guards ──
require_root() {
    if [ "$EUID" -ne 0 ]; then
        fail "This step must be run as root. Use sudo."
    fi
}

require_user() {
    local expected="$1"
    if [ "$(whoami)" != "$expected" ]; then
        fail "This step must be run as user '$expected' (current: $(whoami))"
    fi
}

require_nix() {
    if ! command -v nix &>/dev/null; then
        fail "Nix is not installed. Run step 02-nix first."
    fi
    if ! systemctl is-active --quiet nix-daemon 2>/dev/null; then
        fail "Nix daemon is not running. Run 'sudo systemctl start nix-daemon' first."
    fi
}

# ── System detection ──
is_debian() {
    [ -f /etc/debian_version ]
}

# ── Run a step with header ──
run_step() {
    local label="$1"
    local script="$2"
    heading "$label"
    if [ -x "$script" ]; then
        "$script" || warn "Step completed with warnings"
    else
        warn "Script not found: $script"
    fi
}
