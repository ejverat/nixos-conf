#!/usr/bin/env bash
#
# bootstrap-gear5th.sh — bootstrap the Debian host (gear5th) from the
# nixos-conf flake (Option B: home-manager standalone + shared home modules).
#
# Safe by default: every sudo/destructive step asks for confirmation unless
# --yes is given (headless or AI-agent use; requires passwordless sudo).
#
# Usage:
#   ./bootstrap-gear5th.sh [--yes] [--no-reboot]
#
# Env overrides: REPO_URL, BRANCH, REPO_DIR, EXPECTED_USER
#
# See docs/gear5th-support.md for the full runbook and failure catalog.

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────
REPO_URL="${REPO_URL:-https://github.com/ejverat/nixos-conf.git}"
BRANCH="${BRANCH:-feat/portable-home-manager}"
REPO_DIR="${REPO_DIR:-$HOME/nixos-conf}"
EXPECTED_USER="${EXPECTED_USER:-ejverat}"
ASSUME_YES=0
DO_REBOOT=1

# ── Helpers ────────────────────────────────────────────────────────────────
c_info=$'\033[1;34m'; c_ok=$'\033[1;32m'; c_warn=$'\033[1;33m'; c_err=$'\033[1;31m'; c_end=$'\033[0m'
info() { printf '%s[*]%s %s\n' "$c_info" "$c_end" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$c_ok" "$c_end" "$*"; }
warn() { printf '%s[!]%s %s\n' "$c_warn" "$c_end" "$*"; }
err()  { printf '%s[x]%s %s\n' "$c_err" "$c_end" "$*"; }
step() { printf '\n==> %s\n' "$1"; }

confirm() {
    # $1 = question. Returns 0 on yes.
    if [ "$ASSUME_YES" -eq 1 ]; then return 0; fi
    local ans
    read -r -p "$1 [y/N] " ans
    [[ "$ans" =~ ^[YySs]$ ]]
}

die() { err "$1"; exit "${2:-1}"; }

require_pwless_sudo() {
    if ! sudo -n true 2>/dev/null; then
        if [ "$ASSUME_YES" -eq 1 ]; then
            die "--yes requires passwordless sudo (sudo -n true) on this machine" 2
        fi
    fi
}

# ── Steps ──────────────────────────────────────────────────────────────────
preflight() {
    step "Preflight"

    [ "$(id -u)" -eq 0 ] && die "Run this script as your user, never as root (home-manager activation must not run as root)."

    local user
    user="$(whoami)"
    if [ "$user" != "$EXPECTED_USER" ]; then
        die "User mismatch: this machine's user is '$user' but the flake host modules/hosts/gear5th/default.nix pins '${EXPECTED_USER}'.
Edit home.username and home.homeDirectory in that file (or regenerate with EXPECTED_USER=$user) and re-run." 2
    fi
    ok "user: $user"

    command -v git >/dev/null || die "git is required (sudo apt install git)." 2
    command -v nix >/dev/null || die "Nix is not installed. Install it first:
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install"
    nix --version | sed 's/^/[+] detected: /'
    nix flake --help >/dev/null 2>&1 || die "This Nix does not support flakes (nix-command + flakes experimental features)."

    if [[ -d "$HOME/.dotfiles" && ! -L "$HOME/.dotfiles" ]]; then
        warn "A previous ~/.dotfiles checkout exists (now managed declaratively by home-manager)."
        if confirm "Move it to ~/.dotfiles.bak? [y/N]"; then
            mv "$HOME/.dotfiles" "$HOME/.dotfiles.bak"
            ok "moved ~/.dotfiles -> ~/.dotfiles.bak"
        else
            warn "Leaving ~/.dotfiles in place; activation may fail if targets collide."
        fi
    fi
}

clone_or_update_repo() {
    step "Repository ($REPO_DIR, branch $BRANCH)"

    if [ -d "$REPO_DIR/.git" ]; then
        info "existing checkout; updating"
        git -C "$REPO_DIR" fetch --quiet origin
        if ! git -C "$REPO_DIR" show-ref --verify --quiet "refs/heads/$BRANCH"; then
            git -C "$REPO_DIR" checkout -q -b "$BRANCH" "origin/$BRANCH"
        else
            git -C "$REPO_DIR" checkout -q "$BRANCH"
        fi
        git -C "$REPO_DIR" pull --ff-only --quiet origin "$BRANCH"
    else
        git clone --quiet --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"
    fi

    [ -f "$REPO_DIR/flake.nix" ] || die "flake.nix missing after clone; wrong branch? ($BRANCH)"
    ok "repo ready at $REPO_DIR"
}

verify_flake() {
    step "Flake sanity check"
    # Forces evaluation of the whole home configuration (catches module errors).
    (cd "$REPO_DIR" && nix eval --raw .#homeConfigurations.gear5th.activationPackage.drvPath >/dev/null)
    ok "flake evaluates: homeConfigurations.gear5th.activationPackage"
}

build_activation() {
    step "Build home-manager activation package (first build downloads several GB)"
    (cd "$REPO_DIR" && nix build .#homeConfigurations.gear5th.activationPackage)
    ok "build finished"
}

setup_login_shell() {
    step "Portable zsh as login shell"

    # The login shell must be a STABLE path: ~/.nix-profile/bin/zsh follows the
    # current home-manager generation. Pinning a store path (…/zsh-5.9.2/bin/zsh)
    # goes stale on every switch (the wrapper is rebuilt with a new hash), so
    # config changes silently stop applying and GC can break the login.
    local zsh_bin="$HOME/.nix-profile/bin/zsh"
    if [ ! -x "$zsh_bin" ]; then
        die "$zsh_bin not found: run the home-manager activation before setting the login shell." 2
    fi

    local current_shell
    current_shell="$(getent passwd "$(whoami)" | cut -d: -f7)"
    if [ "$current_shell" = "$zsh_bin" ]; then
        ok "login shell already set to the portable wrapper ($zsh_bin)"
        return
    fi
    case "$current_shell" in
        /nix/store/*)
            warn "current login shell is a stale store path ($current_shell); replacing it with the profile symlink" ;;
    esac

    if ! grep -qxF "$zsh_bin" /etc/shells 2>/dev/null; then
        confirm "Add $zsh_bin to /etc/shells (sudo)? [y/N]" || die "aborted by user: login shell step"
        require_pwless_sudo
        echo "$zsh_bin" | sudo tee -a /etc/shells >/dev/null
        ok "/etc/shells updated"
    fi

    confirm "Change your login shell to $zsh_bin (sudo usermod)? [y/N]" || die "aborted by user: login shell step"
    require_pwless_sudo
    sudo usermod -s "$zsh_bin" "$(whoami)"
    ok "login shell changed (takes effect at next login/reboot)"
}

activate() {
    step "Activate home-manager (as your user, no sudo)"
    (cd "$REPO_DIR" && nix run .#homeConfigurations.gear5th.activationPackage)
    ok "home-manager activated; profile at ~/.nix-profile"
}

disable_display_managers() {
    step "Display manager handling"

    local dms=(gdm sddm lightdm ly greetd)
    local found=0
    local dm
    for dm in "${dms[@]}"; do
        if systemctl is-enabled --quiet "$dm" 2>/dev/null; then
            found=1
            warn "$dm is enabled and owns a tty; niri needs the tty."
            if confirm "Disable $dm (sudo systemctl disable --now $dm)? [y/N]"; then
                require_pwless_sudo
                sudo systemctl disable --now "$dm"
                ok "disabled $dm"
            else
                warn "Skipped. If $dm autologs to tty1, niri will never start."
            fi
        fi
    done

    if [ "$found" -eq 0 ]; then
        ok "no display manager enabled"
    fi

    # Make sure a login prompt exists on tty1.
    if ! systemctl is-enabled --quiet getty@tty1 2>/dev/null; then
        require_pwless_sudo
        sudo systemctl enable getty@tty1
    fi
    ok "getty@tty1 available for the niri login"
}

summary() {
    step "Done"
    cat <<EOF

Validation checklist (after login, inside the niri session):
  echo \$XDG_SESSION_TYPE        # should print wayland
  niri msg version
  tmux new -s test && exit      # prefix is C-a (Ctrl+a, then :kill-session)
  nvim --version | head -1
  wezterm start &
  pi --version

First-run extras on Debian:
  sudo apt install build-essential xclip    # nvim/lazy compile deps + tmux clipboard
  mkdir -p ~/.config/zsh; chmod 600 ~/.config/zsh/secrets.zsh
    # export OPENCODE_API_KEY="..." / export DEEPSEEK_API_KEY="..."

Provider keys for pi go in ~/.config/zsh/secrets.zsh (sourced by the dotfiles .zshrc).

Diagnostics live in docs/gear5th-support.md — hand it to an AI agent if something breaks.
EOF
}

# ── Argument parsing ───────────────────────────────────────────────────────
for arg in "$@"; do
    case "$arg" in
        --yes|-y) ASSUME_YES=1 ;;
        --no-reboot) DO_REBOOT=0 ;;
        -h|--help) sed -n '1,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown argument: $arg (try --help)" 2 ;;
    esac
done

# ── Main ───────────────────────────────────────────────────────────────────
info "gear5th bootstrap — branch $BRANCH"
preflight
clone_or_update_repo
verify_flake
build_activation
activate
setup_login_shell
disable_display_managers
summary

if [ "$DO_REBOOT" -eq 1 ]; then
    if confirm "Reboot now to land in the niri session on tty1? [y/N]"; then
        require_pwless_sudo
        sudo reboot
    else
        info "Not rebooting. Log out and log in on tty1 (or reboot later) to start niri."
    fi
fi