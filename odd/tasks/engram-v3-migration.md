# Feature: migrate Engram to v3 with gentle-engram 0.2.0

## Goal

Close the coupling the pi ecosystem bump left open. `gentle-engram` is
deliberately held at 0.1.12 because every later version requires instance
identity from the `engram` binary, and this repository pins the server at 1.20.0.
Move both to the current matching pair — `engram` 3.0.0 and `gentle-engram` 0.2.0
— without risking `~/.engram/engram.db`.

## Decisions

- **Target the matching pair, not the nearest legal one.** `gentle-engram` 0.2.0's
  release notes ship the same breaking change as `engram` 3.0.0's: `mem_update`
  and `mem_delete` require an explicit `expected_project` and forward it to
  `PATCH`/`DELETE /observations/{id}`. 0.2.0 ↔ 3.0.0 is therefore the pair, and
  0.2.0 against a 2.x server would repeat the 0.1.16 ↔ 1.20.0 mistake in the
  opposite direction.
- **The gate is a copy test, not release age.** `engram` 3.0.0 is one day old;
  that is a reason to test, not a reason to skip.
- **Back up first, with the server stopped.** The live database carries a 4.2 MB
  WAL, so a copy taken while the server writes can be torn.
- **Inject the version through ldflags.** `cmd/engram/main.go` declares
  `var version = "dev"` and `.goreleaser.yaml` sets it with `-X main.version`,
  so the Nix build currently produces a binary that reports `engram dev` and
  answers `Could not check for updates`. Passing the version makes the binary
  self-describing, which matters because the extension reasons about the
  server's version.
- **Keep `CGO_ENABLED = 0`.** v3.0.0 still uses `modernc.org/sqlite` (pure Go),
  so the existing setting stays valid.
- **Never bump the server or the extension alone.** The comment in
  `modules/features/engram.nix` records this; this feature is the one place where
  both move together.

## Established facts

Recon done before writing this plan, so no task below rests on an assumption:

- `go.mod` at v3.0.0 moves the module path to
  `github.com/Gentleman-Programming/engram/v3`; `cmd/engram` still exists; it
  requires Go 1.25.10 and nixpkgs ships 1.26.7.
- The three generated `*_templ.go` files are committed next to their `.templ`
  sources, so `go build` needs no `templ` run.
- The store schema is only ever created with `CREATE TABLE IF NOT EXISTS` and
  v3's changelog states plainly that **no migration rewrites or backfills** the
  columns; v2 and v3 instead carry explicit legacy handling (nullable
  `sessions.project`, forward adoption of unowned sessions, `ifnull()` reads in
  every scan site). A database upgraded from 1.20.0 is a population the current
  code already knows about.
- `engram doctor` is read-only by default: it "does not repair data, apply
  migrations, delete rows, or mutate sync cursors". `engram doctor repair`
  supports `--plan`, `--dry-run` and `--apply`, and an apply backs the database
  up under the writer lock. `docs/DOCTOR.md` itself says to test on a fixture or
  backup clone, "never by experimenting on the production database".
- `ENGRAM_DATA_DIR` selects the data directory (default `~/.engram`), which is
  what makes an isolated copy test possible.
- The extension's own breaking change lands on this repository's habits:
  `mem_update` and `mem_delete` will require an explicit `expected_project`.
- `gentle-engram` 0.2.0 drops `pi-mcp-adapter` from its peers and moves `typebox`
  to a peer; both are provided by the host at runtime, so the local typebox
  install stays harmless.

## Pre-computed inputs

Derived during recon; the build re-verifies them, so treat a mismatch as a
signal, not a nuisance.

| Input | Value |
| --- | --- |
| `engram` 3.0.0 source (`fetchFromGitHub`) | `sha256-W5LNPxS4qa0fo/ejVQueR13cSLrtVydnsdgLGgIZ4uI=` |
| `gentle-engram` 0.2.0 tarball (`fetchurl`) | `sha512-c/1mAVfkGc6M5C8cGjwqCRo7cgckI26fXczDVLnT1cwLrw6Am//IFUxLZM6Gs5LOFhp0OARY+GJ+XQ/An4YAZA==` |
| `engram` 3.0.0 `vendorHash` | resolved by the first build's mismatch error |

## Tasks

1. [x] Back up the live database with the server stopped
       (`~/.engram/{engram.db,engram.db-wal,engram.db-shm}`), and confirm the
       copy opens read-only.
2. [x] Add `engram` 3.0.0 to `modules/features/engram.nix` (version, source hash,
       `vendorHash`, `main.version` ldflags) and build it; confirm `--version`
       reports 3.0.0 and `instance-id` is a real subcommand.
3. [x] Copy test: run the 3.0.0 binary against the database copy through
       `ENGRAM_DATA_DIR`, run `engram doctor` read-only, then exercise a read and
       a write. This is the gate. **Result: passed.**
4. [x] Bump `gentle-engram` to 0.2.0 in the same commit as the server.
5. [x] Isolated end-to-end: scratch agent directory plus the copied database,
       confirming `mem_*` works and that `mem_update`/`mem_delete` now demand
       `expected_project`.
6. [x] Activate on chopper, verify against the live database, and keep the backup
       until the result is confirmed. **Built and verified here; the activation
       itself is the user's step (sudo needs a password).**
7. [x] Record the new `expected_project` contract where the tools are used.

## Fallback

If the copy test finds anything wrong with v3.0.0, the pair to fall back to is
`engram` 2.2.1 (2026-09-25) with `gentle-engram` 0.1.16 or 0.2.0 — both satisfy
the instance-identity requirement that 1.20.0 fails, and 2.2.1 is a week old
rather than a day.

## Verification evidence

- **Task 1**: baseline before touching anything: 89 sessions, 123 observations,
  308 prompts, 11 projects. The server was stopped with `SIGTERM` (the 5-day-old
  process died; the extension respawned a new one minutes later and `mem_stats`
  returned the same counts), so the copy was taken with no writer. Pristine backup
  at `~/.engram/backups/pre-v3-20261002-194652/`: `engram.db`, `engram.db-wal`,
  `engram.db-shm`, plus a logical `engram export` (592,236 bytes) whose own counts
  matched the baseline exactly, with sha256 recorded for the database and WAL. The
  copy opens and reports the baseline counts. One self-inflicted false alarm worth
  remembering: `pgrep -f "engram serve"` matches the checking script's own command
  line, so it reported the server as alive after it had already died; `ps -p <pid>`
  or a bracketed pattern is the honest check. Baseline `doctor` on 1.20.0: 4
  checks, 3 ok, 1 warning (a pre-existing CUDA project/directory drift).
- **Task 2**: `engram` 3.0.0 builds at
  `/nix/store/ccw8jbzz36qp4nw7j2x8zqgbg2brc0ni-engram-3.0.0` with
  `vendorHash = sha256-roVQ+K9Hsz0qi61f+zzb+JvgleOmBHSMcKfhwhI0snQ=`. `--version`
  reports `engram 3.0.0` instead of `dev`, which is the point of the ldflag, and
  `instance-id` answers with an id where 1.20.0 said `unknown command`. Checked
  that running it against the live data directory did **not** touch the database:
  it only writes a sibling `.instance-id` (33 bytes, mode 600) and its lock file,
  and the live `engram.db` keeps its size and mtime.
- **Task 3 (the gate): passed.** v3.0.0's `doctor` runs 11 checks against 1.20.0's
  4. On a fresh copy of the backup: 7 ok, 2 warnings, 2 errors.
  - ok: `invalid_session_identity`, `orphaned_observation_session`,
    `orphaned_pending_relations`, `manual_session_name_project_mismatch`,
    `sqlite_lock_contention`, `sync_mutation_required_fields` — every check that
    concerns memory content.
  - warnings: `session_project_directory_mismatch` (the same pre-existing CUDA
    drift 1.20.0 already reported) and `ambiguous_active_runtime_sessions`
    (4 active candidates for `nixos-conf`, i.e. today's own sessions).
  - errors: `sync_target_closed_space` (11 `foreign_sync_target` findings — stale
    `cloud:<project>` targets with pending unacked mutations, left over from
    earlier cloud experiments) and `mcp_inspection_error` (a corrupt
    `~/.gemini/config/mcp_config.json`, a file outside Engram).
  - Neither error is caused by v3: both are pre-existing conditions that only
    v3's larger check set can see, and `sync_target_closed_space` has a repair
    path (`engram doctor repair --check sync_target_closed_space`).
  - Read: project-scoped `stats` on the copy (25 sessions / 79 observations / 143
    prompts) matches the baseline's `nixos-conf` row exactly, and `search` returns
    real observations with their content.
  - Write: `save` created observation #125 (79 -> 80) and it reads back.

**Staging note**: between task 2 and task 4 the server pin sat in the working tree
without a commit, on purpose: activating 3.0.0 while the extension was still at
0.1.12 would break `mem_update` and `mem_delete`, since v3 requires
`expected_project` and only the matching extension sends it. Both pins then moved
in the single commit `8376f07`.

- **Task 4**: `gentle-engram` 0.2.0 builds at
  `/nix/store/yyzwnb85gm2qcxfrz0jzq6qz9qxcr7pk-gentle-engram-0.2.0`; its `index.ts`
  carries `expected_project` (4 occurrences) and `instance-id` (6). Both pins moved
  in one commit (`8376f07`). In 0.2.0 typebox is a peer that pi aliases to its own
  copy at load time; the local install is kept so the package stays self-contained.
- **Task 5**: the 3.0.0 server was started against the backup copy on port 7439
  (`ENGRAM_DATA_DIR=/tmp/engram-copytest`; its health reports `version: 3.0.0` and
  an `instance_id`), leaving the live server on 7437 untouched. The server-side
  contract was proven directly over HTTP, which is what a 0.1.x extension would
  hit: `PATCH /observations/125` without the parameter answers `400
  expected_project must be a valid non-empty project name`, with the correct owner
  `200` (revision 2), and with a wrong owner `409 expected_project does not match
  observation owner`. Extension level: a scratch agent directory (settings.json
  pointing at the 0.2.0 and gentle-pi 3.7.0 paths, `auth.json` symlinked) ran pi
  0.87.1 with `ENGRAM_URL=http://127.0.0.1:7439` and `ENGRAM_BIN` at the 3.0.0
  binary — `mem_save` created #126, `mem_update` with `expected_project` succeeded,
  `mem_delete` with `hard_delete` removed it, and a follow-up search found nothing.
  The live database was untouched throughout (its server still reports 1.20.0, and
  its counts moved only with this session's own writes). Test server stopped and
  the scratch directory removed.
- **Task 6**: `nix flake check` passes, chopper's system toplevel and gear5th's
  `activationPackage` both build, the activation resolves `gentle-engram-0.2.0` for
  `settings.json`, and `engram-3.0.0` is in `environment.systemPackages` (so the
  `engram` on PATH becomes 3.0.0). **The activation itself has not been run**: sudo
  requires an interactive password on chopper. Keep the backup until the live
  result is confirmed.
- **Task 7**: the contract is recorded in three places — the package comment in
  `modules/features/engram.nix`, this document, and a new `## Memory` section in
  `~/.pi/agent/AGENTS.md` (global agent instructions, so it is not repository
  content). The section states the `expected_project` requirement with its `400`
  and `409` answers, the equivalent raw-HTTP form, where the backups live, and the
  version coupling between server and extension.
