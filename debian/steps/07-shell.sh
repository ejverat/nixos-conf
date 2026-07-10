#!/usr/bin/env bash
# 07-shell.sh — Shell setup + dotfiles
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

heading "07: Shell + dotfiles"

USER_HOME="$HOME"
USER_NAME="$(whoami)"

# ── PATH to include nix-managed binaries ──
ensure_nix_path() {
    local rc_files=("$USER_HOME/.bashrc" "$USER_HOME/.profile" "$USER_HOME/.zshrc")
    local line='export PATH="$HOME/.nix-profile/bin:$PATH"'

    for rc in "${rc_files[@]}"; do
        if [ -f "$rc" ] && ! grep -q '\.nix-profile/bin' "$rc" 2>/dev/null; then
            echo "" >> "$rc"
            echo "# Added by nixos-conf bootstrap" >> "$rc"
            echo "$line" >> "$rc"
            msg "Added nix PATH to $(basename "$rc")"
        fi
    done

    # Ensure current session has it
    export PATH="$HOME/.nix-profile/bin:$PATH"
}

# ── Zsh as login shell ──
ensure_zsh_shell() {
    local nix_zsh="$USER_HOME/.nix-profile/bin/zsh"

    if [ ! -x "$nix_zsh" ]; then
        warn "Nix-managed zsh not found at $nix_zsh"
        info "The debian-bundle may not have been installed yet."
        return
    fi

    if ! grep -q "$nix_zsh" /etc/shells 2>/dev/null; then
        echo "$nix_zsh" | sudo tee -a /etc/shells > /dev/null
        msg "Added $nix_zsh to /etc/shells"
    fi

    local current_shell
    current_shell=$(getent passwd "$USER_NAME" | cut -d: -f7)
    if [ "$current_shell" != "$nix_zsh" ]; then
        info "Changing login shell to Nix-managed zsh…"
        sudo chsh -s "$nix_zsh" "$USER_NAME"
        msg "Login shell changed to zsh (effective after next login)"
    else
        msg "Login shell is already Nix-managed zsh"
    fi
}

# ── Oh My Zsh ──
ensure_omz() {
    if [ -d "$USER_HOME/.oh-my-zsh" ]; then
        msg "Oh My Zsh already installed"
    else
        info "Installing Oh My Zsh…"
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended 2>/dev/null || warn "Oh My Zsh install failed"
    fi

    if [ -d "$USER_HOME/powerlevel10k" ]; then
        msg "Powerlevel10k already installed"
    else
        info "Installing Powerlevel10k…"
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$USER_HOME/powerlevel10k" 2>/dev/null || warn "Powerlevel10k install failed"
    fi
}

# ── Stow dotfiles ──
ensure_dotfiles() {
    if [ ! -d "$USER_HOME/.dotfiles" ]; then
        warn "~/.dotfiles not found. Skipping stow."
        info "Clone your dotfiles and re-run this step:"
        info "  cd && git clone <url> .dotfiles"
        return
    fi

    if ! command -v stow &>/dev/null; then
        info "Installing stow…"
        sudo apt install -y stow
    fi

    info "Stowing config/ → ~/.config/…"
    cd "$USER_HOME/.dotfiles"
    if [ -d config ]; then
        stow --restow -d config -t "$USER_HOME/.config" . 2>/dev/null || warn "stow config/ had issues"
    fi

    info "Stowing home/ → ~/…"
    if [ -d home ]; then
        stow --restow -d home -t "$USER_HOME" . 2>/dev/null || warn "stow home/ had issues"
    fi

    msg "Dotfiles stowed"
}

# ── Run ──
ensure_nix_path
ensure_zsh_shell
ensure_omz
ensure_dotfiles

msg "Shell setup complete"
