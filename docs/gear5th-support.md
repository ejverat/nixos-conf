# gear5th Support Guide (AI-agent assisted)

You are helping with **gear5th**, a Debian machine that is configured from the
`nixos-conf` flake through **home-manager standalone** (no NixOS). The user
also owns `chopper` (NixOS), which shares this same repo. Read this document
before touching the machine, and follow the failure catalog when something
breaks.

## 1. What this machine is

- Debian (x86_64-linux), user normally `ejverat` (verify: `whoami`).
- Nix installed via the Determinate Systems installer (or equivalent).
- The session is **niri** (Wayland) started **from tty1 by the login shell** —
  there is no display manager managing it (Debian DMs cannot load nix-store
  wayland sessions).
- Login shell is a Nix wrapper zsh (`myZshPortable`) that prepends the Nix
  profile to `PATH` and `exec niri` on tty1 when no display is running.
- Secrets for pi are NOT Nix-managed here: they live in
  `~/.config/zsh/secrets.zsh` (sourced by the dotfiles `.zshrc` when present).
  On chopper they come from root sops; that migration is a planned follow-up.

## 2. How the configuration maps

| Path (Repo) | Role |
| --- | --- |
| `flake.nix` | inputs; home-manager input follows `nixpkgs` |
| `modules/parts.nix` | flake-parts; imports `home-manager.flakeModules.default` (makes `flake.homeModules` mergeable) |
| `modules/features/*.nix` | each exports `flake.homeModules.<name>` (shared user layer) and/or `flake.nixosModules.<name>` (chopper only) |
| `modules/hosts/gear5th/default.nix` | `homeConfigurations.gear5th`; wires the shared home modules + host identity (inline HM module) |
| `dotfiles/` | vendored portable configs (nvim, tmux, wezterm, `.zshrc`, cht.sh) |
| `scripts/bootstrap-gear5th.sh` | one-shot bootstrap (clone → build → shell → activate → DM) |
| `odd/tasks/portable-home-manager.md` | design decisions + verification evidence |

Runtime materialization (symlinks into the nix store, created by
home-manager): `~/.dotfiles/config/{nvim,tmux,wezterm}`,
`~/.dotfiles/home/.zshrc`, `~/.dotfiles/utilities/cht.sh`,
`~/.config/wezterm/wezterm.lua`, `~/.config/noctalia/settings.json`,
`~/.oh-my-zsh`, `~/.oh-my-zsh-custom/...`, `~/.zsh/zsh-autosuggestions`,
`~/powerlevel10k`.

**Important:** chopper and gear5th share this repo. Do **not** edit
`modules/features/*`, `dotfiles/`, or the host module without explicit user
consent — a bad change lands on both machines. When in doubt, diagnose and
report instead of editing.

## 3. Agent rules

1. Run home-manager activation/builds as the **user**, never with `sudo`
   (`sudo -n true` must stay unauthenticated for headless runs).
2. Never delete user data: move conflicting paths to `*.bak` instead.
3. Never disable a service or reboot without `sudo systemctl` confirmation;
   when the user is present, ask first.
4. Gather exact evidence before fixing: paste the full error, not a paraphrase.
5. Ground anything GPU-related in the fact that **kernel drivers come from
   Debian** while niri brings nixpkgs' mesa.
6. Always check `git status`/branch first: the repo must be on
   `feat/portable-home-manager` (until merged to `main`).

## 4. Health checklist

```sh
whoami                                   # expect ejverat
# Login shell must be the STABLE profile path (a /nix/store/... store path
# goes stale on every home-manager switch and GC can break login):
getent passwd "$USER" | cut -d: -f7      # expect /home/ejverat/.nix-profile/bin/zsh
grep -c "$HOME/.nix-profile/bin/zsh" /etc/shells   # registered for chsh
~/.nix-profile/bin/home-manager --version
nix flake show "path:$HOME/nixos-conf" --json >/dev/null   # flake evaluates
ls -l ~/.dotfiles/config/nvim ~/.config/noctalia/settings.json   # symlinks
cd ~/nixos-conf && git status --short && git branch --show-current
```

Inside a niri session:

```sh
echo "$XDG_SESSION_TYPE"        # wayland
niri msg version
niri msg action do-screen-record --output 2>/dev/null || true   # compositor alive
```

## 5. Bootstrap

```sh
cd ~/nixos-conf
./scripts/bootstrap-gear5th.sh                # interactive
./scripts/bootstrap-gear5th.sh --yes --no-reboot   # headless (needs passwordless sudo)
```

The script clones `https://github.com/ejverat/nixos-conf.git` on branch
`feat/portable-home-manager` into `~/nixos-conf` (override with
`REPO_URL`/`BRANCH`/`REPO_DIR` env vars). It will not run as root, prompts
before every destructive step, and validates the flake before activating.

## 6. Failure catalog

### 6.1 `home-manager switch` / activation fails with "existing file is in the way"
**Cause:** a leftover real file/dir at a path home-manager wants to symlink
(e.g. an old `~/.dotfiles` checkout, apt oh-my-zsh, `~/.config/wezterm`).
**Fix:**
```sh
mv ~/.dotfiles ~/.dotfiles.bak        # plus any other path named in the error
home-manager switch --flake ~/nixos-conf#gear5th
```
Do not `rm -rf`; move.

### 6.2 Activation fails with a Nix/module option error
**Cause:** repo drift, wrong branch, or an edit to shared modules.
**Fix:**
```sh
cd ~/nixos-conf && git status --short && git log --oneline -5   # what changed?
git rev-parse HEAD        # compare with chopper's HEAD when reporting
nix flake check           # eval-only smoke test, catches module errors
```
Report the full error + `HEAD` hash. Do not fix forward on gear5th alone.

### 6.3 niri does not start on tty1
niri's full output is teed to `$XDG_RUNTIME_DIR/niri-console.log` (readable over
SSH), so the first diagnostic is always:

```sh
tail -80 /run/user/$(id -u)/niri-console.log
```

Then checks in order:
```sh
loginctl list-sessions                       # a TTY session for the user?
getent passwd "$USER" | cut -d: -f7          # login shell is the wrapper zsh?
systemctl is-enabled gdm sddm lightdm ly greetd 2>/dev/null   # DM owning tty1?
tty                                        # which tty are you on?
```
If a DM is enabled: `sudo systemctl disable --now <dm>`. If the shell is
wrong — or the tty1 login is running an old wrapper (symptom: the teed log
file never appears after a switch) — the login shell was pinned to a stale
store path. Fix it to the stable profile path:

```sh
ls -l ~/.nix-profile/bin/zsh
echo "$HOME/.nix-profile/bin/zsh" | sudo tee -a /etc/shells
sudo usermod -s "$HOME/.nix-profile/bin/zsh" "$USER"
```

To see the niri error directly, from tty2 log in and run `niri` manually — the
wrapper zsh executes `exec niri` only on tty1 (`myZshPortable` zshrc), so tty2
gives you a plain shell for debugging.

### 6.4 niri session renders with software GPU / artifacts / screen stays on console logs
First clarify whether niri is even seeing the display (the running instance is
usually healthy — check via IPC before killing anything). Note niri >= 26.04
renamed the IPC socket to `niri.<wayland-display>.<pid>.sock` (no `niri.sock`)
and dropped the `-L` log flag:

```sh
SOCK=$(ls /run/user/1000/niri.*.sock 2>/dev/null | head -1)
NIRI_SOCKET=$SOCK niri msg version
NIRI_SOCKET=$SOCK niri msg outputs      # empty list == niri runs outputless (DRM/modeset problem)
NIRI_SOCKET=$SOCK niri msg workspaces
env WAYLAND_DISPLAY=wayland-1 nix shell nixpkgs#wayland-utils -c wayland-info | grep -A3 wl_output
```

Drivers are Debian's; niri's mesa comes from nixpkgs. **Known root cause on non-NixOS**: nixpkgs libgbm looks for its backend under `/run/opengl-driver/lib/gbm`, a symlink only NixOS creates — on Debian it is missing and niri runs outputless:

```
MESA-LOADER: failed to open dri: /run/opengl-driver/lib/gbm/dri_gbm.so
WARN niri::backend::tty: error adding primary node device ... No such file or directory
```

Fix (creates the symlink from the flake's own mesa + a tmpfiles.d entry so it
survives reboots; re-run after nixpkgs lock updates):

```sh
cd ~/nixos-conf && ./scripts/fix-opengl-driver.sh
sudo pkill -TERM -x niri       # then relogin on tty1
```
```sh
journalctl -b -e | grep -iE 'niri|drm|gpu|vulkan' | tail -40
niri msg version
```
If hardware accel is missing, confirm the Debian GPU drivers are installed
(e.g. `nvidia-driver` or `mesa` from apt) and that the kernel module loads
(`lsmod | grep <driver>`). This is the known early-risk area of the whole
setup — if simple checks don't resolve it, report to the user/chopper side
with the journal excerpt rather than hacking the flake.

### 6.5 `pi` is missing from PATH or crashes at startup
```sh
command -v pi || ls ~/.nix-profile/bin/pi
~/.nix-profile/bin/pi --version
```
The wrapper (`packages.myPi`) bundles `node`/`npm` on `PATH`, so an
`spawn npm ENOENT` here means pi is NOT the wrapper (e.g. an old npm install
is earlier in PATH). Check `type -a pi`. Re-activate home-manager to restore
the profile; never `npm i -g` anything on this machine (the nix profile owns
`~/.nix-profile`).

### 6.6 Noctalia launcher (`Mod+D`) or lock does nothing
```sh
ls -l ~/.config/noctalia/settings.json        # must exist (symlink)
command -v wl-paste cliphist                  # clipboard helpers wanted by settings
```
The repo file `modules/features/noctalia.json` holds the settings; the
runtime file is the raw settings object. If only clipboard features are dead,
install helpers (apt or nix); if the launcher itself is dead, report.

### 6.7 wezterm has no window
Its config sets `config.enable_wayland = false`, so it needs XWayland —
provided by `xwayland-satellite`, which the niri wrapper configures. Check
inside niri: `pgrep -a xwayland-satellite`. If absent, the niri wrapper
wasn't used / reactivate home-manager.

### 6.8 tmux copy doesn't reach the clipboard
`tmux.conf` pipes to `xclip`: `command -v xclip || sudo apt install xclip`.

### 6.9 nvim erroring on first run (missing plugin/compiler)
lazy.nvim clones plugins on first start: needs `git`. Some plugins compile:
```sh
command -v gcc make || sudo apt install build-essential
```

## 7. Updating (routine)

```sh
cd ~/nixos-conf && git pull --ff-only
home-manager switch --flake ~/nixos-conf#gear5th
```
If `git pull` refuses (diverged), do **not** force: report. If the build
fails after an update, run `nix flake check` and report the error + hashes.

## 8. Reporting to the chopper side

Include, in this order:
1. `whoami`, `nix --version`, Debian version.
2. `cd ~/nixos-conf && git rev-parse HEAD && git branch --show-current`.
3. The exact failing command and its full output (or `-v` output).
4. `nix flake check` result.
5. Relevant logs: `journalctl -b -e` excerpts, `nix build` failure tail.
6. The `~/.dotfiles.bak` list if anything was moved.

Do not push, merge, or change shared modules from gear5th. Diagnosis and
fixes that touch `modules/features/*` belong on the chopper side, where the
changes are reviewed on both machines at once.