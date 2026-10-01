# Feature: bump the pi ecosystem to current upstream

## Goal

Bring the four Nix-pinned pieces of the pi ecosystem up to the versions
available upstream, and the one npm-managed plugin with them, without changing
how any of them is wired into the hosts.

| Component | From | To | Pinned in |
| --- | --- | --- | --- |
| `pi-coding-agent` | 0.85.1 | nixpkgs-unstable at bump time | flake input `nixpkgs-pi` (`modules/features/pi.nix`) |
| `gentle-pi` | 3.2.0 | 3.7.0 | `modules/features/gentle-pi.nix` |
| `gentle-ai` | 3.1.0 | 3.7.0 | `modules/features/gentle-pi.nix` |
| `gentle-engram` | 0.1.12 | 0.1.16 | `modules/features/engram.nix` |
| `npm:pi-mcp-adapter` | 2.34.0 | 4.0.0 | `~/.pi/agent/settings.json` (user-level, not in this repo) |

## Decisions

- **`gentle-ai` moves with `gentle-pi`, never alone.** gentle-pi's installer
  (`scripts/gentle-ai-installer.mjs`, `INSTALLER_VERSION`) treats a version
  mismatch as `GENTLE_AI_VERSION_MISMATCH` and refuses to run, and the Nix
  derivation writes the same `integrity.json` the installer would have written.
  Both versions are edited in one commit, and `gentleAiAssetSha256` /
  `gentleAiBinarySha256` are transcribed from that release's own asset table
  (`asset(name, assetSha256, binarySha256, executable)`, in that order).
- **`pi-coding-agent` follows the `nixpkgs-pi` pin, not upstream npm.** Nixpkgs
  lags the published release (it ships the version its cache can build); pinning
  the npm tarball directly would mean carrying a package override in this repo
  forever. The dedicated `nixpkgs-pi` input exists precisely so this bump does
  not drag the whole system nixpkgs with it.
- **`gentle-pi` stays the owner of the gentle-ai runtime.** The Nix derivation
  keeps installing the binary into `$out/.gentle-ai/v<version>/`, so the strict
  package-local resolver keeps working and no code path changes.
- **`pi-mcp-adapter` is updated at the user level**, because it lives in
  `~/.pi/agent/settings.json` as an `npm:` spec that pi reconciles itself at
  startup. It is the one component `nixos-rebuild` cannot move; its major-version
  jump is validated by hand.
- **`context7-mcp@2.2.5` is deliberately left pinned** in `~/.pi/agent/mcp.json`.

## Tasks

1. [x] Create the feature branch and this document.
2. [ ] Bump the `nixpkgs-pi` pin and verify `pi --version`.
3. [ ] Bump `gentle-pi` 3.2.0 -> 3.7.0 with its coupled `gentle-ai` 3.7.0.
4. [ ] Bump `gentle-engram` 0.1.12 -> 0.1.16.
5. [ ] Re-sync the vendored `gentle-profile` links against what gentle-ai 3.7.0
       writes into its config home, if they differ.
6. [ ] Refresh stale version references in comments and docs.
7. [ ] Update `npm:pi-mcp-adapter` 2.34.0 -> 4.0.0 and validate.
8. [ ] Full verification and activation handoff.

## Verification evidence

Filled in as each task closes.

- Task 1: branch `chore/pi-ecosystem-bump` created from `main` (`66545fd`).
