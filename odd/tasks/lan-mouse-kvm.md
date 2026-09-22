# Feature: lan-mouse software KVM between chopper and gear5th

## Goal

Share one physical mouse and keyboard between **chopper** (NixOS, niri) and
**gear5th** (Debian, niri) over the LAN, wired declaratively through this flake.
The cursor crosses at the chopper/gear5th boundary, with chopper on the left and
gear5th on the right. Clipboard sharing is explicitly out of scope: lan-mouse
does not implement it (open roadmap item), and the compositors that would allow
the alternative (Deskflow/Synergy 3) are not niri.

## Context discovered (2026-09-22, verified on chopper)

**niri 26.04 implements exactly the protocol set lan-mouse needs, and none of
the one the libei-based tools need.** Checked against the real binary
(`/nix/store/zvy0rhq84l0x39d6ipg2aligpji3lfb2-niri-26.04/bin/niri`) and the
upstream source tree (`niri-wm/niri`, `src/protocols/virtual_pointer.rs`):

| Protocol | In niri | Used for |
|---|---|---|
| `zwlr_virtual_pointer_manager_v1`, `zwp_virtual_keyboard_manager_v1` | yes | injecting mouse/keyboard |
| `zwlr_layer_shell_v1`, `zwp_pointer_constraints_v1`, `zwp_relative_pointer_manager_v1` | yes | capturing the pointer at the edge |
| `zwp_keyboard_shortcuts_inhibit_manager_v1` | yes (action since 25.02) | stop niri binds while forwarding keys |
| `libei` / `libeis` (EIS server) | **no** (0 matches for `libei`, `libeis`, `ei_handshake`) | the Wayland path of every other KVM |
| `org.freedesktop.portal.RemoteDesktop` / `InputCapture` | **no** | the portal fallback of those tools |

Consequences, with the evidence that establishes them:

| Tool | State | Why it cannot be used here |
|---|---|---|
| **lan-mouse 0.11.0** | active (release 2026-06, commits 2026-09), GPL-3, Rust | **usable**: `layer-shell` capture + `wlroots` emulation |
| Deskflow 1.26.0 | very active (29k stars) | its `CMakeLists.txt` requires `libei >= 1.3` and `libportal >= 0.9.1`; niri has no EIS server |
| Input Leap 3.0.3 | **archived 2025-12** | dead upstream, libei-based Wayland path, no clipboard on Wayland |
| Barrier 2.4.0 | abandoned (2021) | X11 only, no Wayland |
| Synergy 3 | proprietary | same EIS requirement on Wayland |
| waynergy 0.0.17 | client only | needs a Synergy server on X11/Windows/macOS; both hosts are niri |

Upstream niri issues #823 (`Implement input capture portal`), #1966 (`add remote
desktop portal`) and #4228 (`Add Mutter RemoteDesktop support`) are all still
open, so the gap is upstream work, not a configuration mistake.

Two facts that shape the implementation:

1. **The nixpkgs build already carries both needed backends.** Strings in
   `/nix/store/caiyp9ig47bxws9nm3nkwhp8ffbx0bdp-lan-mouse-0.11.0/bin/.lan-mouse-wrapped`
   contain `zwlr_virtual_pointer_manager_v1`, `zwp_virtual_keyboard_manager_v1`,
   `zwlr_layer_shell_v1` and `zwp_keyboard_shortcuts_inhibit_manager_v1`, because
   lan-mouse's default cargo features include `layer_shell_capture` and
   `wlroots_emulation`. Nothing has to be compiled or overridden.
2. **Auto-detection would probe the unusable path first.** Capture backend
   selection iterates `InputCapturePortal` (libei) before `LayerShell`
   (`input-capture/src/lib.rs:329`), so the config pins both backends instead of
   leaving them to detection.

Running environment, measured on chopper:

- Session: `XDG_SESSION_TYPE=wayland`, `XDG_CURRENT_DESKTOP=niri`, niri 26.04.
- `graphical-session.target`, `xdg-desktop-autostart.target` and `niri.service`
  are all active in the user manager, and `WAYLAND_DISPLAY` is in the manager
  environment, so a `graphical-session.target` user unit gets a usable session.
- niri already binds the escape hatch lan-mouse needs:
  `"Mod+Escape" allow-inhibiting=false { toggle-keyboard-shortcuts-inhibit }`
  (`modules/features/niri.nix:161`).
- Network: chopper is `192.168.1.166/24` on `wlo1` (DHCP); gear5th answers in
  1–3 ms. Chopper's firewall opens only UDP 5353 and TCP 8080
  (`modules/hosts/chopper/configuration.nix:211`), so UDP 4242 is new.
- Address discovery is the weak point: `getent hosts gear5th` returned a stale
  `192.168.0.196` (unreachable), while `gear5th.local` answered `192.168.1.159`
  and later `192.168.1.114`, both reachable. The peers are therefore configured
  with an mDNS `hostname` **plus** an `ips` fallback.

## Decisions

- **lan-mouse is the only candidate**, derived from the protocol table above;
  the reason is recorded in the module comment so a future reader does not
  re-open the Deskflow question without checking niri's issue tracker first.
- **Backends are pinned** (`capture_backend = "layer-shell"`,
  `emulation_backend = "wlroots"`): deterministic on niri, and it skips a portal
  round trip that can only fail here.
- **The config is seeded, never symlinked.** lan-mouse rewrites
  `~/.config/lan-mouse/config.toml` when a peer is authorized
  (`authorized_fingerprints`, `src/config.rs:566`), and store paths are
  read-only, so `xdg.configFile` would break authorization. This is the same
  policy as `_preset-seed.nix` and the slicer presets: seed only when the file is
  missing, and the application's own copy always wins.
- **`authorized_fingerprints` is left empty on purpose.** The first authorization
  is a human action in the GUI (compare the peer's fingerprint, click
  *Authorize*); committing a fingerprint into the repo would freeze a value that
  belongs to the pair of machines.
- **The firewall port lives in the feature's `nixosModules`**, not in the host
  file. This is a deliberate deviation from the current convention (avahi's 5353
  and 8080 are written in `configuration.nix`): port 4242 belongs to the
  feature's contract, so disabling the feature closes the port.
- **The user service mirrors upstream's `service/lan-mouse.service`**
  (`After`/`BindsTo`/`WantedBy=graphical-session.target`) rather than kanshi's
  `default.target`. The daemon injects through Wayland protocols, so it must not
  start before the compositor; upstream's unit states that contract and the
  target is confirmed active on this host.
- **Per-host values go through an option** (`nixosConf.lan-mouse.config`,
  `nullOr lines`, default `null`), following `kanshi`: the shared module stays
  host-agnostic and each host declares its own side of the boundary.

## Tasks

1. Add `modules/features/lan-mouse.nix` (NixOS layer: package + UDP 4242; home
   layer: package, seed option, user service) and wire chopper: import the home
   module and declare chopper's client entry (`position = "right"` → gear5th).
   Commit: `b3c51ba` — feat(lan-mouse): add the shared software-KVM module and
   wire chopper.
2. Wire gear5th: import the home module in the standalone host and declare its
   client entry (`position = "left"` → chopper); document the Debian-side
   prerequisites in `docs/gear5th.md` (mDNS resolution, no firewall rule by
   default, interactive authorization). Commit: `2726108` — feat(gear5th): wire
   lan-mouse and document its Debian-side prerequisites.
3. Record verification evidence (below) in this file and add the portability note
   to `README.md`. Commit.
4. First-run runbook for the user (authorize both fingerprints, confirm the
   crossing direction, address stability). Commit.

## Risks

- **DHCP churn on both ends.** chopper's lease is DHCP and gear5th answered on
  two different addresses in the same session. Without a DHCP reservation the
  pair decays to "edit `ips` in a user-owned file". Recommended follow-up:
  reserve both addresses on the router.
- **mDNS is not trustworthy here.** `gear5th.local` returned two different A
  records and `getent hosts gear5th` returned a stale address on another subnet;
  this is why `ips` is a required fallback and not decoration.
- **Debian-side firewall and hostname resolution are outside this flake.** If
  gear5th runs nftables/ufw, UDP 4242 must be opened there by hand; the module
  can only do it for chopper.
- **No clipboard.** A future reader expecting copy/paste across machines will be
  disappointed; it is listed under Follow-ups with the reason.
- **Input injection on niri is a protocol bet**: the niri side of it is
  `zwlr_virtual_pointer_manager_v1` + `zwp_virtual_keyboard_manager_v1`, which
  niri implements today. A regression there would surface as a dead pointer after
  the crossing, not as a broken build.

## Verification evidence

Run on 2026-09-22 from chopper once the wiring was in place. Every command below
was executed; an independent read-only verification pass then re-ran the same
checks and reported PASS on all of them (its own caveats are repeated under "Not
verified here").

**Build and evaluation**

| Command | Result |
|---|---|
| `nix flake check` | `all checks passed!` (evaluates `nixosConfigurations.chopper`, `nixosModules.lan-mouse` and `homeConfigurations`) |
| `nix build --no-link --print-out-paths .#homeConfigurations.gear5th.activationPackage` | `/nix/store/xn781f5khqy8zcjnyy99qg44xacfm9rc-home-manager-generation` |

**The generated unit** reproduces upstream's contract on both hosts (`find -L
<generation> -name lan-mouse.service`):

```
ExecStart=/nix/store/caiyp9ig47bxws9nm3nkwhp8ffbx0bdp-lan-mouse-0.11.0/bin/lan-mouse daemon
After=graphical-session.target
BindsTo=graphical-session.target
WantedBy=graphical-session.target
```

plus an enabled symlink at `graphical-session.target.wants/lan-mouse.service`, and
no `config.toml` anywhere under `home-files/` — which is the point: the file stays
writable for the application.

**Both pinned backends do initialize on this niri.** The seed text was rendered
with `nix eval --raw` into a throwaway `XDG_CONFIG_HOME` and handed to the real
binary, which loads the config before dispatching any subcommand:

```
[INFO lan_mouse] using config: "/tmp/lm-smoke/lan-mouse/config.toml"
[INFO input_capture] using capture backend: layer-shell
[INFO input_emulation] using emulation backend: wlroots
[INFO input_capture::layer_shell] active outputs:
[INFO input_capture::layer_shell]  * eDP-1 1366x768 @pos (0, 0)
```

`test-emulation` against **both hosts' rendered configs** reported `using
emulation backend: wlroots` (exit 124 from `timeout`, as expected), so each
seeded TOML parses and the `emulation_backend` key is honored. `test-capture` and
the daemon with a live client were deliberately not run: both take over the
pointer of the running session.

**The seed never overwrites.** The activation block extracted from the generated
script was run with `HOME` in a throwaway directory. With no file it created one
(mode 0644, byte-identical to the seed); with a pre-existing file (mode 0600,
distinctive content) it reported `keeping the existing …` and left both the
content and the mode untouched.

**Not verified here, and why**

- The peer side cannot be exercised from chopper: nothing runs the daemon on
  gear5th until that host is switched and the fingerprint is authorized. What is
  verified is that gear5th's configuration builds and that its rendered config
  parses with the real binary.
- "Only lan-mouse can work here" is a consequence of the protocol evidence at the
  top of this document (niri has no EIS server and no InputCapture portal;
  Deskflow's `CMakeLists.txt` requires `libei >= 1.3` and `libportal >= 0.9.1`). It
  was not established by running Deskflow, Input Leap or Synergy on this host.
- The Debian-packaging statement in `docs/gear5th.md` (lan-mouse is not in Debian,
  `deskflow` is) comes from the Debian sources index, and the upstream issue
  numbers and cargo default features in the module comment come from the GitHub
  API and lan-mouse's `Cargo.toml`. None of those are re-checkable offline.
- Address reachability is time-bound: `192.168.1.159` and `192.168.1.114` both
  answered in 1–2 ms during the setup session and `gear5th.local` resolved to
  `192.168.1.159`. Both hosts are on DHCP leases, which is what the pinned
  `ips` list in each config is compensating for until the addresses are reserved.

## Follow-ups

- Clipboard sharing would require a compositor with an EIS server (GNOME 45+ or
  KDE 6.1+) on at least one side, i.e. replacing niri; re-check
  niri#823/#1966/#4228 before promising it.
- DHCP reservations for both hosts, so `ips` stops being a moving target.
- If the pair is ever used across different networks, DTLS fingerprint
  authorization has to be repeated per new peer identity.
