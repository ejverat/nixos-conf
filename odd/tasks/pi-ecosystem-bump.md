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
2. [x] Bump the `nixpkgs-pi` pin and verify `pi --version`.
3. [x] Bump `gentle-pi` 3.2.0 -> 3.7.0 with its coupled `gentle-ai` 3.7.0.
4. [x] Bump `gentle-engram` 0.1.12 -> 0.1.16.
5. [x] Re-sync the vendored `gentle-profile` links against what gentle-ai 3.7.0
       writes into its config home, if they differ.
6. [x] Refresh stale version references in comments and docs.
7. [x] Update `npm:pi-mcp-adapter` 2.34.0 -> 4.0.0 and validate.
8. [x] Full verification and activation handoff.

## Verification evidence

- **Task 1**: branch `chore/pi-ecosystem-bump` created from `main` (`66545fd`).
- **Task 2**: `flake.lock` moves `nixpkgs-pi` to 2026-09-29
  (`b4fd65b198c599cbe814fcb9f42d25d021595ec9`). The wrapped package builds from
  the binary cache as `pi-coding-agent-0.87.1`, `pi --version` prints `0.87.1`,
  and the wrapper still prepends nodejs 24.21.0 (the `npm:` reconciliation in
  `~/.pi/agent/settings.json` keeps working). Nixpkgs-unstable is at 0.87.1
  while upstream npm publishes 0.99.2; the pin follows nixpkgs by decision.
- **Task 3**: `gentle-pi-3.7.0` builds. `.gentle-ai/v3.7.0/gentle-ai --version`
  prints `gentle-ai 3.7.0`, and the written `integrity.json` has the exact key
  order the installer's own `signedReleaseManifest` builds. Both gentle-ai
  digests were re-derived from the downloaded archive before pinning: the
  archive sha256 and the extracted binary sha256 match the 3.7.0 asset table
  byte for byte. The bundled installer diffs against 3.2.0 in 55 lines and only
  version constants and digests change, so the runtime layout and the manifest
  shape are untouched. `pnpmDeps` keeps the 3.2.0 hash on purpose:
  `pnpm-lock.yaml` is byte-identical between the two tags (243 resolutions in
  both) and the build reports that same hash back. Fixed alongside: `bin/` was
  never copied into `$out`, so the `gentle-shell` launcher `package.json`
  declares was missing since before the 3.2.0 pin.
- **Task 4**: `gentle-engram-0.1.16` builds with every file the tarball declares,
  and its local `typebox` is 1.3.30, which still satisfies the tarball's
  `^1.1.38`.
- **Task 5**: no re-sync is needed. `lib/agent-profiles.ts` is byte-identical
  between 3.2.0 and 3.7.0 (empty diff), `PROFILES_VERSION` is 1, and the live
  `~/.pi/gentle-ai/profiles.json` carries exactly that kind and version. The
  script is not shipped by either package: its text appears nowhere in gentle-pi
  3.7.0, `gentle-ai --help` exposes no profile command, and `gentle-ai sync` in a
  fresh `HOME` writes only state and telemetry files. `gentle-profile list` and
  `current` run and report that the live routing equals the stored `bonus`
  profile. The comments claiming the runtime provides the script were corrected.
- **Task 6**: no stale live references remain. `pi.nix` and `flake.nix` state the
  relationship (gentle-pi's floor is still 0.85.1) and the main nixpkgs pin still
  ships 0.84.4, so both stay true. `portable-home-manager.md:67` records 0.85.1 as
  evidence of a closed task and is deliberately left alone; rewriting it would
  falsify that record.
- **Task 7**: installed 4.0.0 with `pi update --extension npm:pi-mcp-adapter`;
  `~/.pi/agent/npm/package.json` now pins `^4.0.0`. Its peer range includes
  `^0.87.0`, so the pinned 0.87.1 satisfies it. Two 4.0.0 changes would have
  silently removed working capability, so the config was migrated first:
  `mcpScript` is now opt-in, and the adapter no longer reads `<agent dir>/mcp.json`
  (confirmed in its own `config.ts`, where the loaded global source is now
  `mcp-adapter.json`). `~/.pi/agent/mcp.json` was moved to `mcp-adapter.json` with
  identical content (backup: `mcp.json.bak-20260930-181519`) and `settings.scriptMode`
  was set to `true` to preserve `mcpScript`. Verified against the installed 4.0.0
  code: `getPiGlobalConfigPath()` resolves `mcp-adapter.json`, `loadMcpConfig()`
  returns `context7`, the parsed settings report `scriptMode: true`, and
  `getLegacyMcpMigrationNotices()` is empty. The native dependency loads
  (`@napi-rs/keyring` + `keyring-linux-x64-gnu`). End to end in ephemeral
  sessions: `mcp({})` reports `0/1` servers, `mcp({ connect: "context7" })`
  connects and lists `context7_resolve-library-id` and `context7_query-docs`,
  `mcp({ server: "context7" })` returns the same two, and `mcpScript` with
  `emit("script-mode-ok")` returns `script-mode-ok`. `mcp({ server })` asking for
  an explicit connect first is not a regression: the running 2.34.0 session
  returns the identical message. The `~/.pi/agent` changes are user-level state,
  not repository content; `modules/features/pi.nix` had its two comments about
  the old `mcp.json` path updated.
- **Task 8**: `nix flake check` passes both eval checks (chopper and gear5th,
  deep evaluation, no compilation). All four packages build, gear5th's
  `homeConfigurations.gear5th.activationPackage` builds, and chopper's
  `nixosConfigurations.chopper.config.system.build.toplevel` builds. The
  activation scripts resolve to the new store paths (`gentle-pi-3.7.0`,
  `gentle-engram-0.1.16`), which is what will be merged into `settings.json`.
  A dry run of the post-activation state was run in an isolated agent dir
  (`PI_CODING_AGENT_DIR` pointed at a scratch copy of `settings.json` with the
  new store paths, `auth.json` symlinked rather than copied, scratch dir removed
  afterwards): pi 0.87.1 starts and loads gentle-pi 3.7.0 (`gentle_review*`,
  `subagent_*`, `todo`, `codegraph`, `session_worktree_register`),
  gentle-engram 0.1.16 (`mem_*`, including the new `mem_list_projects`,
  `mem_pin`, `mem_unpin`) and the 4.0.0 adapter (`mcp`); with
  `mcp-adapter.json` present, `mcpScript` appears too. The `omen-alpha` model
  warning reproduces there, which confirms it is unrelated to this bump.
  Working tree clean, seven commits on the branch.
  **Activation is pending and belongs to the user**: `sudo` requires an
  interactive password on chopper, so `sudo nixos-rebuild switch --flake
  .#chopper` (and `home-manager switch --flake ~/nixos-conf#gear5th` on gear5th)
  have not been run. After activating, restart pi and confirm `pi list` shows
  both new store paths.

## Open items

- **Pi version skew for `gentle-shell`.** `gentle-pi`'s package keeps a bundled
  `@earendil-works/pi-coding-agent` at 0.85.1 in `node_modules`, and the
  launcher's resolution order prefers that bundled copy over `pi` on `PATH`, so
  `gentle-shell` would still run 0.85.1 while the system runs 0.87.1. Nothing in
  this repo invokes `gentle-shell`, so this is latent. Fixing it well means
  either exporting `GENTLE_SHELL_PI` or dropping the bundled copy; both change
  runtime behavior and are the user's call.
- **`opencode-go/omen-alpha`** in `enabledModels` draws a no-matching-model
  warning on startup. It is independent of this bump (the local model catalog
  holds no `opencode-go` entries at all) and is left untouched.
- The upstream GitHub repository was renamed to `gentle-shell`. The Nix pin keeps
  the old name on purpose because GitHub's rename redirect resolves it and the
  npm package is still `gentle-pi`; switching would only rename the source store
  path.
