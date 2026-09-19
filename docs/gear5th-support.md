# gear5th Support Guide (AI-agent assisted)

You are helping with **gear5th**, a Debian machine that is configured from the
`nixos-conf` flake through **home-manager standalone** (no NixOS). The user
also owns `chopper` (NixOS), which shares this same repo. Read this document
before touching the machine, and follow the failure catalog when something
breaks.

## 1. What this machine is

- Debian (x86_64-linux), user normally `ejverat` (verify: `whoami`).
- Nix installed via the Determinate Systems installer (or equivalent).
- The session is **niri** (Wayland). Two supported launch paths:
  - **Display manager (recommended)**: `scripts/install-niri-session.sh` writes
    `/usr/share/wayland-sessions/niri.desktop` (absolute Exec to the stable
    profile path of `niri-session`) and enables GDM. Needed with Bluetooth
    keyboards, which are awkward at a bare tty login prompt.
  - **tty1 autostart**: the portable zsh wrapper `exec`s niri from tty1 when no
    display manager owns it (see `myZshPortable`); inert while GDM runs.
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
| `scripts/install-niri-session.sh` | GDM session file for niri + enable GDM/bluetooth |
| `scripts/fix-pam-unix-chkpwd.sh` | setuid PAM helper so the lock screen accepts the password |
| `scripts/debian-system-services.sh` | Debian system layer: apt packages, systemd services, firmware, Bluetooth (`--check` is read-only) |
| `scripts/seed-gentle-profiles.sh` | seeds the gentle-profile routing profiles from the vendored copies (no SSH/network needed between hosts) |
| `scripts/fix-opengl-driver.sh` | recreate the `/run/opengl-driver` tree nixpkgs expects |
| `scripts/diag-gear5th.sh` | read-only fact collector for session/GPU/seat issues |
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

**Layer boundary:** Nix owns the user configuration; Debian owns the system. If
something needs apt, systemd system units, dbus/udev integration or firmware, it
belongs to `scripts/debian-system-services.sh` (or apt directly), never to the
flake. If it is a user program, config file or session, it belongs to a
`flake.homeModules` module.

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
before every destructive step, validates the flake before activating, and
backs up conflicting files automatically during activation (§6.1), then
verifies that the key managed paths really are symlinks.

## 6. Failure catalog

### 6.1 `home-manager switch` / activation fails with "existing file is in the way"
**Cause:** a leftover real file/dir at a path home-manager wants to symlink
(e.g. an old `~/.dotfiles` checkout, apt oh-my-zsh, `~/.config/wezterm`,
`~/powerlevel10k`, `~/.zsh/zsh-autosuggestions`,
`~/.config/noctalia/settings.json`).
**Fix:** move the path aside, never delete it.

`scripts/bootstrap-gear5th.sh` does this automatically: its activation step
exports `HOME_MANAGER_BACKUP_EXT=bak`, so every colliding path is moved to
`<path>.bak` during activation instead of aborting the run. That environment
variable is the standalone-mode mechanism (what `home-manager switch -b bak`
exports); the `home-manager.backupFileExtension` / `backupCommand` *options*
only exist when home-manager runs as a NixOS/nix-darwin module and are **not**
available in this standalone configuration.

By hand:

```sh
# automatic (equivalent to what the script does):
cd ~/nixos-conf
HOME_MANAGER_BACKUP_EXT=bak home-manager switch --flake .#gear5th
# or move the paths named in the error first, then switch:
mv ~/.dotfiles ~/.dotfiles.bak        # plus any other path named in the error
home-manager switch --flake ~/nixos-conf#gear5th
```

Do not `rm -rf`; move. Two caveats:

- Activation refuses to back a path up onto an existing backup
  (`Existing file 'X.bak' would be clobbered by backing up 'X'`). Move the stale
  `X.bak` aside first; never reach for `HOME_MANAGER_BACKUP_OVERWRITE`, it
  destroys the previous backup.
- Legacy relative symlinks that pointed into the old `~/.dotfiles` checkout
  become dangling the moment it is moved. The important one is `~/.config/zsh`:
  home-manager does not manage it, but the managed `.zshrc` sources
  `~/.config/zsh/secrets.zsh` from it, so it must be a real directory:

  ```sh
  mv ~/.config/zsh{,.bak} && mkdir -p ~/.config/zsh   # then ~/.config/zsh/secrets.zsh
  ```

  The rest (`~/.config/{alacritty,rofi,waybar,hypr,awesome}`,
  `~/.config/install*.sh`, `~/.config/.luarc.json`, `~/.themes`,
  `~/.config/cht.sh`, ...) are inert leftovers from the pre-Nix stow setup.

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

With a display manager instead, check the session entry:

```sh
cat /usr/share/wayland-sessions/niri.desktop   # Exec must be an ABSOLUTE path
ls -l ~/.config/systemd/user/niri.service      # niri-session starts this unit
systemctl --user start niri.service            # try it manually to see errors
```

`Exec=niri-session` (the package default) never resolves in a DM's minimal PATH,
and DMs do not read nix-store session dirs — re-run
`scripts/install-niri-session.sh` if the file looks wrong.

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

Drivers are Debian's; niri's mesa comes from nixpkgs. **Known root cause on non-NixOS**: nixpkgs patches its GL stack to look under `/run/opengl-driver`, a tree only NixOS creates. On Debian both stages fail:

```
MESA-LOADER: failed to open dri: /run/opengl-driver/lib/gbm/dri_gbm.so
WARN niri::backend::tty: error adding primary node device ... No such file or directory
<after fixing the GBM symlink only>
DEBUG niri::backend::tty: ... Unable to obtain a valid EGL Display.
WARN niri::backend::tty: error adding primary node device ... no allocator available for device
```

libglvnd's compiled-in EGL vendor search dirs are
`/run/opengl-driver/share/glvnd/egl_vendor.d:/etc/glvnd/egl_vendor.d:/usr/share/glvnd/egl_vendor.d`,
hence the EGL failure until that subdirectory exists too.

Fix (mirrors the NixOS tree from the flake's own mesa + a tmpfiles.d entry so
it survives reboots; re-run after nixpkgs lock updates):

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

### 6.10 Lock screen rejects the password

nixpkgs' `pam_unix.so` execs `/run/wrappers/bin/unix_chkpwd` (the setuid wrapper
path NixOS creates). On Debian that path is missing, so a user process cannot
verify a password and the noctalia/quickshell lock (`Quickshell.Services.Pam`)
always fails.

```sh
ls -l /run/wrappers/bin/unix_chkpwd          # must exist and be setuid
ls -l /usr/local/libexec/nix-unix_chkpwd     # -rwsr-xr-x root root
ls -l /etc/pam.d/noctalia-lock               # minimal service
cd ~/nixos-conf && ./scripts/fix-pam-unix-chkpwd.sh   # creates/repairs all three
journalctl --user -u niri -e | grep -i -E 'pam|auth'  # locker log if it still fails
```

Re-run the script after nixpkgs lock updates (the store hash changes).

### 6.11 GDM does not start at boot

Two Debian-specific traps, both handled by `scripts/install-niri-session.sh`:

1. Debian's `gdm.service` is **static** (`systemctl is-enabled gdm` prints
   `static`): it has no `[Install]` section, so `systemctl enable gdm` cannot
   create boot wiring on its own.
2. The `display-manager.service` alias is what `graphical.target` normally uses,
   and disabling the DM (tty-mode bootstrap) deletes it.

The script writes a drop-in that restores the install metadata and enables the
unit again:

```sh
sudo mkdir -p /etc/systemd/system/gdm.service.d
sudo tee /etc/systemd/system/gdm.service.d/10-nixos-conf-enable.conf >/dev/null <<'EOF'
[Install]
Alias=display-manager.service
WantedBy=graphical.target
EOF
sudo systemctl daemon-reload && sudo systemctl enable gdm && sudo reboot
```

Diagnostics:

```sh
systemctl get-default                                   # must be graphical.target
systemctl is-enabled gdm                                # enabled (static = not wired)
ls -l /etc/systemd/system/display-manager.service
ls -l /etc/systemd/system/graphical.target.wants/gdm.service
systemctl status gdm -l --no-pager | head -30
journalctl -b -u gdm --no-pager | tail -40
```

If GDM starts and then crashes, the journal above says why (missing greeter
packages, GL, etc.). A much lighter alternative that also lists the session
file:

```sh
sudo apt install greetd tuigreet
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