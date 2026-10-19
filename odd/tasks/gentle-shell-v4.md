# Feature: gentle-shell 4.3.0 + pi 1.2.0 on both hosts

## Goal

Move the Nix-built Pi ecosystem to the current upstream releases: pi
0.87.1 -> 1.2.0 (nixpkgs-unstable) and gentle-shell (npm `gentle-pi`)
3.7.0 -> 4.3.0, including the gentle-ai binary that gentle-pi pins.

## Why

- The user asked for the latest gentle-shell and pi.
- gentle-pi v4.x is the current line: the upstream repo was renamed to
  `gentle-shell`, the npm package is still `gentle-pi`, and v4.x requires
  `@earendil-works/pi-coding-agent >= 1.2.0`. There is no 3.x release newer
  than the installed 3.7.0, so updating gentle-shell forces the pi bump.
- The package-local gentle-ai binary must match gentle-pi's
  `INSTALLER_VERSION` or the installer fails closed with
  `GENTLE_AI_VERSION_MISMATCH`; v4.3.0 pins **4.2.0**.

## Facts gathered (source-verified)

| Item | Value | Source |
|------|-------|--------|
| gentle-shell latest tag | `v4.3.0` | `git ls-remote` |
| gentle-pi src hash (v4.3.0) | `sha256-rmuIk4IudViiz4nDJ646lCOHLfHIAboKmH/RdIqkpf4=` | `nix-prefetch-url --unpack` |
| gentle-ai `INSTALLER_VERSION` in v4.3.0 | `4.2.0` | `scripts/gentle-ai-installer.mjs:40` |
| gentle-ai asset | `gentle-ai_4.2.0_linux_amd64.tar.gz` | same |
| gentle-ai asset sha256 | `552c1642fd10f5d96cfe9bb1cc3b66b30eb47d3074cc7ca0559b598eb086defc` | installer `asset()` + recomputed |
| gentle-ai binary sha256 | `9212c7b16ea9abfe93e3a16b29d8390e7762b5c07730cf05df1f3e7892ff96a4` | installer `asset()` + recomputed |
| gentle-ai bundle fetchurl hash | `sha256-VSwWQv0Q9dls/puxzDtmsw60fTB0zHygVZtZjrCG3vw=` | `nix hash convert` over the downloaded asset |
| pi 1.2.0 in nixos-unstable | `pi-coding-agent.version = 1.2.0` | `nix eval github:NixOS/nixpkgs/nixos-unstable#pi-coding-agent.version` |
| pnpm lockfile v4.3.0 | `lockfileVersion 9.0`; not the v3.x tree, so the hash changed (the earlier "218 vs 214 entries" count in this doc did not reproduce and was dropped from the code comments) | raw `pnpm-lock.yaml` |
| v4.3.0 runtime deps | `@heyhuynhgiabuu/pi-pretty` only; `pi-tui`, `pi-coding-agent`, `pi-ai`, `typebox` are optional peers | `package.json` |

Other notes:

- `nixpkgs-unstable` still wraps `$out/bin/pi` with ripgrep+fd only
  (`postFixup`), so `modules/features/pi.nix`'s `nodejs`-on-PATH wrapper stays
  necessary and unchanged.
- **Correction found by the build (supersedes an earlier assumption):** v4.3.0's
  `resolveBundledCli()` (`bin/gentle-shell.mjs`) uses
  `import.meta.resolve("@earendil-works/pi-coding-agent")` and, when it resolves,
  prefers that copy over `pi` on PATH. The old story — a `<pkg>/package.json`
  lookup failing through an `exports` map — no longer applies: v4.3.0's
  `package.json` has no `exports` field. Dropping the auto-installed SDK copy is
  still correct, and now for a stronger reason: it makes the PATH fallback
  structural (`import.meta.resolve` throws `ERR_MODULE_NOT_FOUND` inside the
  store path) instead of accidental.
- pnpm auto-installs the optional peers, so the built `node_modules` still
  carries `@earendil-works/pi-tui`, `pi-ai`, `pi-agent-core`, `pi-codemode`,
  `pi-mcp` and `pi-telemetry` at 1.2.0 plus `typebox`. pi 1.2.0 aliases
  `@earendil-works/*` to its own copies at extension load, so those are dead
  weight, not a correctness risk.
- v4.3.0's launcher also enforces `MIN_PI_VERSION = "1.2.0"`, independently
  confirming the `flake.nix` comment.
- The upstream rename (`gentle-pi` repo -> `gentle-shell`) keeps resolving
  through GitHub's rename redirect, so `repo = "gentle-pi"` in the pin stays as
  it is until the redirect stops working.
- `scripts/install-gentle-ai.mjs` resolves the package root as two levels up
  from `scripts/`, and installs into `<packageRoot>/.gentle-ai/v<version>/`;
  the derivation's existing layout is still correct.
- The integrity manifest is `JSON.stringify` of
  `{version, asset, assetSha256, binarySha256}` plus a newline; the derivation
  already writes exactly that byte sequence.

## Scope and non-goals

In scope: `flake.lock` (nixpkgs-pi input), `modules/features/gentle-pi.nix`
(pi input usage stays in `pi.nix`), feature docs.

Non-goals: bumping gentle-engram / engram (`0.2.0` / `3.0.0` stay as they are;
the user asked for gentle-shell and pi), adopting gentle-shell's bundled
`~/.gentle-shell` installation, the upstream installer wizard, or the
`gentle-shell upgrade` command. This repo keeps its declarative Nix pin.

## Constraints

- `gentleAiVersion` and the gentle-pi tag must move together; the binary
  reports its version and the installer rejects a mismatch.
- `pnpmDeps` hash must be recomputed: the lockfile changed.
- The install phase's copy list must match the new `package.json` `files`
  array (`assets bin contracts docs extensions lib prompts runtime scripts
  skills tests themes package.json README.md LICENSE`).
- pi is consumed from the dedicated `nixpkgs-pi` pin, so only that input moves;
  the main `nixpkgs` pin stays put.
- TDD: **off**. Source: repository evidence — no test runner for Nix pins.
  Checks are builds plus runtime probes.

## Tasks

| ID | Task | Route |
|----|------|-------|
| B1 | Update the `nixpkgs-pi` input to the revision that ships pi 1.2.0 and confirm the eval | delegated writer (multi-file write rule: `flake.lock` + `modules/features/gentle-pi.nix`) |
| B2 | Bump `gentle-pi` 3.7.0 -> 4.3.0: version, src hash, pnpmDeps hash, install phase, comments | delegated writer (same unit) |
| B3 | Bump the gentle-ai bundle 3.7.0 -> 4.2.0: version, asset name, both digests, fetchurl hash, integrity.json | delegated writer (same unit) |
| B4 | Build `.#packages.x86_64-linux.gentle-pi`, inspect the installed tree and the package-local gentle-ai binary | delegated writer (focused build, in-delegation verification) |
| B5 | Apply the switch; verify `pi --version`, the extension loads, gentle-ai reports 4.2.0, and memory tools still work | parent, with user go-ahead |
| B6 | Update docs and commit the work unit | parent |

## Acceptance criteria

1. `nix build .#packages.x86_64-linux.gentle-pi` succeeds and the store path is
   `...-gentle-pi-4.3.0`.
2. `$out/.gentle-ai/v4.2.0/gentle-ai --version` prints `gentle-ai 4.2.0`, and
   `sha256sum` equals `9212c7b1...`.
3. `pi --version` reports 1.2.0 after the switch.
4. `~/.pi/agent/settings.json` lists only the new store paths (no stale 0.87.1
   or 3.7.0 entries).
5. A real pi session loads gentle-shell and gentle-engram without a tool-name
   conflict; `mem_*` tools answer and the gentle-ai binary resolves.
6. `nix flake check` still evaluates both hosts.

## Risks

- pi 1.0 changed the TUI to fullscreen by default. User-visible, not a break.
- gentle-engram 0.2.0 was validated against pi 0.87.1. If pi 1.2.0 breaks the
  extension, the fallback is bumping engram/gentle-engram as a separate
  feature; B5 is where that would surface.
- The pnpmDeps hash is discovered by an intentional failed build (fake hash),
  then pinned.
- The user-writable `~/.pi/agent/settings.json` is rewritten by activation; the
  merge is additive and prunes the old store paths by regex.

## Progress

- B1 done: `nixpkgs-pi` re-locked to `fe13242281a67641c0102cdb1087f0ebe586c7df`
  (2026-10-15), which ships pi 1.2.0; every other lock node is byte-identical.
- B2 done: `gentle-pi` 3.7.0 -> 4.3.0 (src hash and pnpmDeps hash recomputed;
  install-phase and peer comments rewritten).
- B3 done: gentle-ai bundle 3.7.0 -> 4.2.0 (version, asset name, both digests,
  fetchurl hash, integrity.json).
- B4 done: builds inspected; see the evidence below.
- B5 done: switch applied, `niri.service` MainPID unchanged, runtime probes
  passed.
- B6 done in this commit.

## Verification evidence

Delegated writer (routes recorded in the task table), parent spot check, and the
applied generation:

- `nix flake update nixpkgs-pi`: `b4fd65b198c5...` (2026-09-29) ->
  `fe13242281a6...` (2026-10-15); re-run is a no-op.
- `nix eval --raw .#packages.x86_64-linux.myPi.name` -> `pi-coding-agent-1.2.0`
  (re-run by the parent as the spot check).
- `nix build .#packages.x86_64-linux.gentle-pi` ->
  `/nix/store/dg0hflrfvrx3qqy97k18b2pr4mgqvavf-gentle-pi-4.3.0`.
- `sha256sum <store>/.gentle-ai/v4.2.0/gentle-ai` -> `9212c7b1...96a4` and
  `--version` -> `gentle-ai 4.2.0`; `integrity.json` is the exact canonical
  manifest with the pinned digests.
- `ls <store>/node_modules/@earendil-works` -> `pi-agent-core pi-ai pi-codemode
  pi-mcp pi-telemetry pi-tui`, with **no** `pi-coding-agent`, so the SDK shadow
  cleanup took effect.
- `nix flake check --no-build` -> exit 0.
- `home-manager switch --flake .#gear5th` -> exit 0; `niri.service` MainPID
  `187709` before and after; `sd-switch --dry-run` listed neither niri nor any
  restart, only `Starting units: kanshi.service, sops-nix.service`.
- `~/.pi/agent/settings.json` now lists
  `/nix/store/dg0hflrfvrx3qqy97k18b2pr4mgqvavf-gentle-pi-4.3.0` and
  `/nix/store/yyzwnb85gm2qcxfrz0jzq6qz9qxcr7pk-gentle-engram-0.2.0`; the 3.7.0
  entry is gone. `pi --version` -> `1.2.0`.
- `pi list` -> both packages resolved.
- Real session probe: `pi --print --no-session --offline ...` loaded the
  gentle-pi 4.3.0 extensions and answered, with only a benign warning that its
  own `codemode` shadows the built-in one.
- Real memory probe: `pi --print --no-session --no-builtin-tools -t mem_stats ...`
  returned live counts (`total_observations: 141`), so gentle-engram 0.2.0 loads
  and executes under pi 1.2.0.
- Known benign change: pi 1.x runs the TUI fullscreen by default (`tuiMode`
  setting still selects `regular`).

## Commit identities

- _this commit_: chore(pi): bump pi to 1.2.0 and gentle-shell to 4.3.0

## Delivery strategy

- Forecast: ~90 authored changed lines across both features, well under the
  ~400-line budget. Strategy: default `ask-on-risk` (no chain needed).
- Branch plan: `fix/session-safe-switch` first; `chore/gentle-shell-v4` stacked
  on it locally so the gear5th switches keep the session-safety fix. Pull
  request order is the user's decision.

## Next step

Feature closed. Optional follow-ups (not authorized here): bump gentle-engram /
engram as a separate feature, or review the codemode shadow warning.
