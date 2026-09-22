# nixos-conf

Dendritic Nix configuration for two machines:

| Host | OS | Managed by |
| --- | --- | --- |
| `chopper` | NixOS | `nixosConfigurations.chopper` (`nixos-rebuild switch --flake .#chopper`) |
| `gear5th` | Debian | `homeConfigurations.gear5th` (home-manager standalone) |

**Reinstalling a machine?** Each host has a rebuild runbook with the exact order of
commands and what to back up first:
[docs/chopper.md](docs/chopper.md) · [docs/gear5th.md](docs/gear5th.md).
For gear5th failures there is also the AI-agent troubleshooting catalog in
[docs/gear5th-support.md](docs/gear5th-support.md).

Shared *user-level* features live in `modules/features/*.nix` as
`flake.homeModules.*`, consumed by both hosts (chopper through the home-manager
NixOS module, gear5th through home-manager standalone). System-level features
stay NixOS-only (`flake.nixosModules.*`). Portable dotfiles are vendored in
`dotfiles/` and materialized at
`~/.dotfiles` by the `dotfiles` home module, so the wrapper packages
(`wrapper-modules`) reference the same paths on both machines.

## Rebuild chopper (NixOS)

```sh
sudo nixos-rebuild switch --flake .#chopper
```

chopper's user-level configuration runs through the home-manager NixOS module
(same `flake.homeModules.*` as gear5th), so one command activates both.
Migration record: `odd/tasks/chopper-home-manager.md`.

## Bootstrap gear5th (Debian)

One command covers the whole rebuild: clone, build and activate home-manager, the
login shell, the Debian system layer (`debian-system-services.sh`) and the
non-NixOS integrations (`fix-opengl-driver.sh`, `fix-pam-unix-chkpwd.sh`,
`seed-gentle-profiles.sh`), then the session:

```sh
./scripts/bootstrap-gear5th.sh --dm       # GDM + niri session (recommended)
./scripts/bootstrap-gear5th.sh --tty      # niri started from tty1 instead
./scripts/bootstrap-gear5th.sh --yes      # headless (needs passwordless sudo)
./scripts/bootstrap-gear5th.sh --minimal  # only the flake/home-manager part
```

Every sudo step asks first, and all of them are idempotent, so re-running the
script is safe. The steps below are what it automates — handy for reference or to
re-run one by hand. The full rebuild runbook is
[docs/gear5th.md](docs/gear5th.md); the AI-agent troubleshooting catalog is
[docs/gear5th-support.md](docs/gear5th-support.md).

### 0. System layer (apt + systemd)

Firmware, Bluetooth, audio, printers and hardware modules are Debian's job, not
Nix's:

```sh
./scripts/debian-system-services.sh           # install + enable
./scripts/debian-system-services.sh --check   # read-only report
```

### 1. Install Nix

```sh
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

### 2. Clone and build

```sh
git clone git@github.com:ejverat/nixos-conf.git ~/nixos-conf
cd ~/nixos-conf
nix build .#homeConfigurations.gear5th.activationPackage
```

### 3. Make the portable zsh the login shell

The login shell must be a **stable path** — `~/.nix-profile/bin/zsh` — not the
store path of one build (that goes stale on every switch and GC can break
login). One root command is needed because `chsh` only accepts shells listed
in `/etc/shells`. From the repo on gear5th, after the first activation:

```sh
ls -l ~/.nix-profile/bin/zsh                       # present after activation
echo "$HOME/.nix-profile/bin/zsh" | sudo tee -a /etc/shells
chsh -s "$HOME/.nix-profile/bin/zsh"
```

### 4. Activate home-manager

First activation installs the `home-manager` CLI into the profile, so later
switches are:

```sh
~/.nix-profile/bin/home-manager switch --flake ~/nixos-conf#gear5th
```

or directly:

```sh
nix run ~/nixos-conf#homeConfigurations.gear5th.activationPackage
```

### 5. Start niri (session)

Pick one launch path:

**Display manager (GDM)** — recommended with a Bluetooth keyboard:

```sh
cd ~/nixos-conf && ./scripts/install-niri-session.sh   # session file + enable GDM/bluetooth
./scripts/fix-pam-unix-chkpwd.sh                       # lock screen PAM (setuid helper)
# pair the keyboard (needs it before the greeter is usable):
bluetoothctl power on && bluetoothctl scan on   # put the keyboard in pairing mode
bluetoothctl pair <MAC> && bluetoothctl trust <MAC> && bluetoothctl connect <MAC>
sudo reboot                                      # then pick "Niri" in GDM
```

The session file Execs the stable `~/.nix-profile/bin/niri-session`; that script
re-runs under your login shell (which puts the nix profile on PATH) and starts
the `niri.service` user unit that the niri home module links into
`~/.config/systemd/user/`.

**tty1 autostart** — no display manager:

Debian display managers cannot load wayland sessions from the nix store, so in
this mode niri is started from tty1 by the portable zsh wrapper (`exec niri`
when no display is running). Disable any DM first:

```sh
sudo systemctl disable --now gdm   # or sddm / lightdm / ly
```

Hit Ctrl+Alt+F1 (or reboot) and log in — niri takes over tty1.

### First things to validate on gear5th

- niri session + GPU: drivers stay with Debian; niri brings its own nixpkgs
  mesa. If something misbehaves (`wayland-info`, missing GPU accel), start
  here before touching anything else.
- Provider keys for pi: sops-nix in user mode decrypts `secrets/secrets.yaml`
  with the age identity derived from `~/.ssh/id_ed25519` and renders
  `~/.config/pi-provider-keys.env` (0400), sourced from `zshenv` by the portable
  wrapper. chopper renders the same secrets from root sops to
  `/run/secrets/rendered/pi-provider-keys.env`.

## Portability notes

- `modules/features/*.nix` export the NixOS module (chopper), the home module
  (shared), or both. Home modules receive `flakeSelf`/`flakeInputs` via
  `extraSpecialArgs` (see `modules/hosts/gear5th/default.nix`).
- Keep host-specific HM modules inline in each host's `default.nix`:
  import-tree turns every `.nix` under `modules/` into a flake-parts module,
  which would mis-evaluate a plain home-manager module file.
- Adding a new portable app = add/use the `flake.homeModules.<name>` in the
  feature file and import it in the host's module list.

## Shared application data (OrcaSlicer presets)

An application's data directory is mutable runtime state, so it cannot be
symlinked from the store the way dotfiles are — the store is read-only and the
app writes there. The OrcaSlicer print presets are therefore **seeded**, not
linked:

- `dotfiles/orcaslicer/user-default/` vendors the shareable presets
  (`machine`, `process`, `filament`, 56 files). Everything else in the data
  directory is deliberately out of scope: `.orcaslicer_machine_id` is a
  per-machine UUID, `OrcaSlicer.conf` carries window geometry and recents,
  `system/` is regenerated by the app from its bundled profiles, and
  `printers/`, `cache/`, `log/`, `ota/` and `user_backup-*` are app-managed or
  transient.
- `flake.homeModules.orcaslicer-presets` seeds them into
  `~/.config/OrcaSlicer/user/default/` **only when a file is missing**, so a
  preset edited in the GUI always wins over the vendored one. Register it in a
  host's module list.
- `scripts/slicer-presets.sh` covers the two directions the seed deliberately
  does not, for **both** OrcaSlicer and PrusaSlicer:

```sh
./scripts/slicer-presets.sh orca  status   # read-only: what differs
./scripts/slicer-presets.sh orca  push     # live -> repo (capture edits made in the GUI)
./scripts/slicer-presets.sh orca  pull     # repo -> live (apply repo changes)

./scripts/slicer-presets.sh prusa status
./scripts/slicer-presets.sh prusa push
./scripts/slicer-presets.sh prusa pull
```

Every action accepts `--dry-run`. `pull` backs the live tree up to
`~/.local/state/slicer-presets-backups/<tool>/<timestamp>/` before overwriting
anything — deliberately outside the applications' own directories, so the apps
never see it and, for PrusaSlicer whose presets sit at its config root, the copy
cannot land inside itself. `pull` never deletes files that exist only on the live
side either; that is `push`'s job.
The script was called `orca-presets.sh` while it only handled OrcaSlicer, and the
per-tool differences are now a single lookup, so a third tool is a two-line
addition.

Presets reference system preset names through their `inherits` chains, so every
host sharing them should use the same `nixpkgs-orca` pin. The flake gives that
for free.

## Shared mouse and keyboard (lan-mouse)

chopper and gear5th share one physical mouse and keyboard over the LAN with
lan-mouse, and it is the only tool that can work here: every alternative routes
Wayland input through **libei** (an EIS server on the compositor) or through the
`RemoteDesktop`/`InputCapture` portals, and niri provides neither — Deskflow
requires `libei >= 1.3` plus `libportal >= 0.9.1`, Input Leap was archived in
2025 and Barrier never left X11. What niri does implement is the wlroots input
protocol set (`wlr-virtual-pointer` + `virtual-keyboard` to inject, `layer-shell`
+ `pointer-constraints` to capture), which is what lan-mouse's `wlroots` and
`layer-shell` backends use. The tool-by-tool evidence is in
`odd/tasks/lan-mouse-kvm.md`.

- `flake.homeModules.lan-mouse` is imported by **both** hosts, so the pairing has
  one source of truth; each host declares its own side of the boundary through
  `nixosConf.lan-mouse.config` (chopper sits to the left, gear5th to the right).
  Both configs pin the two backends, because lan-mouse's capture auto-detection
  probes the libei/portal path first and that can only fail on niri.
- The config is **seeded, never linked**: lan-mouse rewrites
  `~/.config/lan-mouse/config.toml` when it persists an authorized peer
  fingerprint, so a store symlink would break authorization. Same policy as the
  slicer presets: the file is copied only when it is missing.
- `flake.nixosModules.lan-mouse` adds the package and **UDP 4242** to chopper's
  firewall, and the daemon runs as the user unit `lan-mouse.service` bound to
  `graphical-session.target` — it injects through the compositor, so it must not
  start earlier.
- Manual, once per pair of machines: authorize the peer's DTLS fingerprint in the
  GUI (the daemon holds the listener and the GUI attaches to it), and on gear5th
  open UDP 4242 if a host firewall is running. Both host docs carry the steps.
- No clipboard: lan-mouse does not implement it. That would require an EIS server
  on at least one side, i.e. a compositor other than niri.
- **The receiving machine's own niri shortcuts do not fire** (niri#403: keys
  injected through the virtual keyboard never reach niri's `binds`, so `Mod+…`
  falls through to the window instead). Application shortcuts are unaffected.
  There is no configuration escape hatch; a fix needs a `uinput`-based emulation
  backend upstream (lan-mouse#465). `Mod+Escape` on the physical keyboard still
  works.

## Roadmap

1. **More apps through the same mechanism**, in batches, when needed on both
   machines. Inventory taken from the archived `debian-migration` draft
   (`archive/debian-migration-draft` tag):
   - desktop: kanshi (HDMI-A-1 + eDP-1 profiles are in the archived tag),
     hyprpicker
   - files: thunar (+ archive-plugin, volman), file-roller, gvfs, tumbler
   - media: gimp, feh, nomacs, imagemagick
   - browsers/comms: firefox, chromium, google-chrome, slack
   - CLI/dev: bat, fd, direnv, tree, pciutils, upower, docker-client, ollama
2. **System layer stays with Debian**: `scripts/debian-system-services.sh`
   installs/enables it (apt + systemd), with `--check` for a read-only report.