# Nix-on-Debian — gear5th / ejverat

Install the **same applications** from your NixOS `chopper` configuration on
Debian 13 using the **Nix package manager**.

## Structure

```
debian/
├── bootstrap.sh           # Root orchestrator — interactive menu or CLI args
├── common.sh              # Shared: colors, logging, guards, utilities
├── steps/
│   ├── 01-prereqs.sh      # System prerequisites (apt, firmware sources)
│   ├── 02-nix.sh          # Install / validate Nix (checks first!)
│   ├── 03-configure-nix.sh# Enable flakes, trusted-users
│   ├── 04-bundle.sh       # nix profile install .#debian-bundle
│   ├── 05-services.sh     # System services (apt + systemd)
│   ├── 06-kernel.sh       # Kernel modules (kvm-intel, amdgpu)
│   ├── 07-shell.sh        # Shell setup + dotfiles stow
│   └── 08-desktop.sh      # Desktop config (niri, Noctalia, kanshi)
└── README.md
```

## Usage

```bash
# Run everything interactively:
cd ~/nixos-conf/debian
./bootstrap.sh

# Run specific steps (CLI):
./bootstrap.sh 1 2 3    # prereqs → nix → configure
./bootstrap.sh 4        # just install the bundle
./bootstrap.sh all      # same as interactive "all"

# Steps are idempotent — safe to re-run any time.
```

## How the bundle works

`modules/debian.nix` (in the repo root) adds a `.#debian-bundle` package to the
flake. It aggregates everything from the NixOS config using `pkgs.buildEnv`:

- **Wrapped apps** from the flake: myNeovim, myTmux, myZsh, myNiri, myNoctalia, myOpencode, claude-code
- **nixpkgs apps**: chromium, google-chrome, firefox, gimp, slack, wezterm, alacritty, etc.
- **Dev tools**: git, gcc, ripgrep, fzf, bat, fd-find, direnv, luarocks

System services (pipewire, NetworkManager, bluetooth, docker daemon, ollama
daemon) are handled by apt + systemd — they need system-level dbus/udev
integration that Nix can't provide on a non-NixOS system.

## Files modified

| File | Change |
|---|---|
| `modules/debian.nix` | **New** — flake module for `.#debian-bundle` |
| `debian/` | **New** — bootstrap scripts |
