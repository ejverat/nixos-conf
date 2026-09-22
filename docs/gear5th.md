# gear5th — Debian host

Disaster-recovery runbook: rebuild this machine from a fresh Debian install.
Everything user-level is in this repo; the system layer stays Debian on purpose.
When something breaks instead of being rebuilt, go to
`docs/gear5th-support.md` (the failure catalog written for an AI agent).

## What this host is

- Debian 13 (x86_64-linux), user `ejverat` with `sudo`, AMD RX 580 (amdgpu).
- Nix from the Determinate installer. **No NixOS here.**
- User configuration: home-manager standalone, `homeConfigurations.gear5th`,
  importing the same `flake.homeModules.*` as chopper (`docs/chopper.md`).
- System: Debian owns kernel, GPU drivers, firmware, systemd services and GDM.
- Session: GDM starts niri from a session file; niri then runs the systemd user
  unit `niri.service`. The login shell is the portable zsh wrapper at the
  **stable** path `~/.nix-profile/bin/zsh`.
- Secrets: sops-nix in user mode, age identity = `~/.ssh/id_ed25519`, rendered to
  `~/.config/pi-provider-keys.env` (0400) and sourced from `zshenv`.

## Before you wipe (back these up)

| What | Path | Why |
|------|------|-----|
| SSH user key | `~/.ssh/id_ed25519` (+ `.pub`) | it *is* this host's sops age identity |
| pi runtime | `~/.pi/` | agent settings, `mcp.json`, `npm/`, sessions, gentle-ai profiles |
| optional | `~/.config/noctalia/settings.json` | home-manager renders it from `modules/features/noctalia.json`, so a backup is optional |

`~/.dotfiles` is **not** needed any more: home-manager materializes it from the
repo (the manual checkout is retired).

## Fresh install, in order

### 0. Base Debian packages

```sh
sudo apt update && sudo apt install -y curl xz-utils git build-essential xclip
```

### 1. Nix

```sh
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh   # or open a new shell
```

### 2. Repo, home-manager and the session

```sh
git clone https://github.com/ejverat/nixos-conf.git ~/nixos-conf
cd ~/nixos-conf
./scripts/bootstrap-gear5th.sh --dm
```

`--dm` enables GDM plus its niri session file and the PAM helper the lock screen
needs. The script also builds and activates the home-manager configuration,
registers the wrapper in `/etc/shells`, sets it as the login shell and verifies
the managed symlinks. It asks before every `sudo` step (`--yes` runs headless,
and `--tty` keeps the display managers disabled and starts niri from tty1
instead).

If the username is not `ejverat`, edit `modules/hosts/gear5th/default.nix`
(`home.username`, `home.homeDirectory`) first.

### 3. Debian system layer (apt + systemd)

```sh
./scripts/debian-system-services.sh           # firmware, bluetooth, audio, printers, tools
./scripts/debian-system-services.sh --check   # read-only report of the same
```

### 4. Non-NixOS integrations (sudo, idempotent, safe to re-run)

```sh
./scripts/fix-opengl-driver.sh     # recreates the /run/opengl-driver tree nixpkgs' libgbm + glvnd expect
./scripts/fix-pam-unix-chkpwd.sh   # setuid helper + /etc/pam.d/noctalia-lock so the lock screen authenticates
./scripts/seed-gentle-profiles.sh  # gentle-profile script + model-routing profiles
```

`fix-opengl-driver.sh` resolves the mesa package from the flake, so run it after
the configuration has been built (step 2 does that). All three are idempotent;
re-run `fix-opengl-driver.sh` after nixpkgs lock updates, because store hashes
change.

### 5. Secrets

`.sops.yaml` lists this host's SSH key as an age recipient.

- Restored `~/.ssh/id_ed25519` from a backup → nothing to do.
- New key → derive its recipient and add it from a host that can still decrypt
  (chopper):

```sh
# on gear5th
nix run nixpkgs#ssh-to-age -- -i ~/.ssh/id_ed25519.pub      # → age1…

# add that age1… to .sops.yaml (keys + creation_rules), commit, push, then:
cd ~/nixos-conf && git pull && sops-updatekeys secrets/secrets.yaml
```

### 6. Verify

```sh
systemctl --user status sops-nix --no-pager | head -3
ls -l ~/.config/pi-provider-keys.env                 # 0400, rendered by sops
zsh -ic 'echo ${DEEPSEEK_API_KEY:+set}'              # set
pi auth check --provider opencode-go --json          # {"status":"ready",…}
command -v gentle-profile && gentle-profile current  # model routing
ls -l ~/.dotfiles/home/.zshrc ~/.config/wezterm/wezterm.lua
getent passwd "$USER" | cut -d: -f7                  # /home/ejverat/.nix-profile/bin/zsh
echo "$XDG_SESSION_TYPE"                             # inside the session: wayland
```

### 7. Shared mouse and keyboard (lan-mouse)

Both hosts run niri, and niri has neither a libei/EIS server nor the
RemoteDesktop/InputCapture portal, so lan-mouse with its `layer-shell` capture and
`wlroots` emulation backends is the only working option here. The binary comes
from nixpkgs through the shared `flake.homeModules.lan-mouse`; **nothing is
installed with apt**. lan-mouse is **not in Debian** — `deskflow` is, and that is
the one that cannot work on niri.

The daemon runs as the systemd user unit `lan-mouse.service`, bound to
`graphical-session.target`:

```sh
systemctl --user status lan-mouse.service --no-pager
```

Two things the flake cannot do for you:

1. If a host firewall runs on this machine (nftables/ufw), allow **UDP 4242**.
   The flake only opens that port on chopper.
2. First-run authorization is interactive: open `lan-mouse`, compare the peer's
   fingerprint (`aa:bb:cc:…`, shown in the General section of the peer) and click
   **Authorize** on the receiving side. lan-mouse then persists the fingerprint
   into `~/.config/lan-mouse/config.toml`, which is why that file is seeded once
   and never managed by Nix.

mDNS is not guaranteed on Debian, so check that the peer's `.local` name resolves
(needs avahi + libnss-mdns):

```sh
getent hosts chopper.local
```

If that fails, the `ips` list in the config is the fallback, and both hosts'
addresses are DHCP leases that should be reserved on the router.

There is no clipboard sharing: lan-mouse does not implement it.

## What is deliberately not in Nix here

- Kernel, GPU drivers, firmware, display manager and systemd system services:
  apt plus `scripts/debian-system-services.sh`.
- Docker and Ollama: that script prints the commands, they are installed by hand.
- `~/.dotfiles`, shell rc edits and PATH hacks: retired, home-manager owns them.

## If something breaks

- `docs/gear5th-support.md` — failure catalog per symptom (GDM/niri session,
  GPU and `/run/opengl-driver`, PAM lock, pi on PATH, noctalia, wezterm and
  XWayland, tmux clipboard, nvim toolchain) plus the reporting contract.
- `./scripts/diag-gear5th.sh` — read-only fact dump (sockets, GPU, seat, DRM,
  PAM paths, baked store paths in the zsh plugins).
- Rollback: `home-manager generations` lists the previous generations and their
  store paths (each one contains an `activate` script you can run), or simply
  re-run the switch from an earlier commit of this repo.

## Related

- `docs/chopper.md` — the NixOS host, sharing every `flake.homeModules.*`.
- `README.md` — repo layout, the `--dm` bootstrap, roadmap.
