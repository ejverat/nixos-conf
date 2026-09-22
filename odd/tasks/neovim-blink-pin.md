# Feature: pin blink.cmp to the v1 line and restore the writable runtime lockfile

## Goal

Neovim starts with an empty `:messages`: `blink.cmp` loads through its v1 API
instead of failing with `blink.cmp v2 requires "saghen/blink.lib"`, the six
plugins that drifted away from the tracked lockfile are back on their pins, and
`stdpath("config")/lazy-lock.json` is writable again so
`scripts/nvim-lock.sh sync` / `seed` behave as their own contract documents.

## Root cause (validated 2026-09-22 on gear5th)

Three facts chained:

1. **The spec follows `main`, and upstream `main` is v2 dev.**
   `lua/plugins/completion.lua` declares `saghen/blink.cmp` with
   `version = false`, i.e. track the branch. Upstream `main` is now blink.cmp
   v2 (dev): `lua/blink/cmp/init.lua` requires Neovim 0.12+ and
   `require("blink.lib")` from the new `saghen/blink.lib` package, and v2 moved
   the Rust matcher from `target/release/` to `lib/`. The v1 pin lives on the
   upstream `v1` branch (tag `v1.10.2` = `78336bc`), which is **not** an
   ancestor of `main`, so the lockfile commit cannot protect a spec that tracks
   the branch.
2. **A `:Lazy update` moved six plugins to their branch HEAD.** Reflog of
   `~/.local/share/nvim/lazy/blink.cmp`: `4b18c32 -> 8219b58` at
   2026-09-22 02:11 (five minutes after the refactor commit was verified with
   the pinned set). Six plugins ended up ahead of the tracked lockfile:

   | plugin | HEAD installed | lockfile pin |
   | --- | --- | --- |
   | blink.cmp | `8219b58` (2026-09-20, v2 dev) | `78336bc` (2026-04-04, v1.10.2) |
   | lazy.nvim | `306a055` (2025-12-17) | `85c7ff3` (2025-11-06) |
   | mini.ai | `6c39ae7` (2026-09-21) | `cb02c54` (2026-09-07) |
   | nvim-platformio.lua | `9878edd` (2026-01-30) | `d5143c8` (2026-09-10) |
   | nvim-web-devicons | `58447c1` (2026-09-21) | `914decf` (2026-09-18) |
   | tree-sitter-manager.nvim | `c59cb96` (2026-09-22) | `1425eac` (2026-09-05) |

   Only blink.cmp crossed a breaking major boundary, which is why it is the
   visible symptom.
3. **The drift was silent because the runtime lockfile is read-only.**
   `stdpath("config")` = `~/.config/nvim` is a stale symlink created
   2025-07-19 by the pre-home-manager installer, pointing at
   `../.dotfiles/config/nvim`, which is read-only store materialization.
   `test -w ~/.config/nvim/lazy-lock.json` fails with `Permission denied`, and
   the path is absent from the current generation's `putter.json` (only
   `.dotfiles/config/nvim` is managed), so home-manager neither creates nor
   removes it. Consequently lazy.nvim cannot persist pins after an update and
   `nvim-lock.sh` cannot `seed` a fresh machine, while its header claims the
   opposite. `odd/tasks/chopper-home-manager.md` (slice 2) told the user to
   `rm ~/.config/nvim`; that cleanup ran on chopper but never on gear5th.

Reproduction (offline, no UI):

```sh
nvim --headless "+lua local ok,e=pcall(require,'blink.cmp'); print(ok,e)" +qa
# false  .../blink/cmp/init.lua:4: blink.cmp v2 requires "saghen/blink.lib" ...
```

## Decision

Pin the plugin spec to the v1 line and repair the lockfile path.

- **A (chosen) — `version = "1.*"` on the blink.cmp spec.** lazy.nvim resolves
  the latest v1 tag (`v1.10.2` = `78336bc`, exactly the tracked pin), the spec
  keeps the v1 configuration API it was written against, no new dependency and
  no extra weight. A future `:Lazy update` can no longer drag it into v2 dev.
- **B (rejected) — migrate to blink.cmp v2.** Needs `saghen/blink.lib`, the new
  `require("blink.cmp").build()` step and the `lib/` artifact path, on an
  unreleased dev branch, plus an extra dependency. It contradicts the "lighter
  config" goal of `odd/tasks/neovim-minimal-refactor.md`, and v2 stays a dev
  target rather than a released one.
- **C (rejected) — leave the spec alone and rely on `:Lazy restore`.** Fixes
  today's symptom and re-breaks on the next `:Lazy update`, which is exactly how
  this incident started.

The runtime lockfile symlink is repaired alongside the pin because it is the
mechanism that let the drift go unnoticed: with a writable
`~/.config/nvim/lazy-lock.json`, `:Lazy update` records what it resolved and
`nvim-lock.sh sync` / `check` regain their documented meaning.

## Constraints carried over (do not regress)

- `performance.rtp.reset = false` and `performance.reset_packpath = false` stay:
  the wrapper prepends `$HOME/.dotfiles/config/nvim` to the rtp and sources
  `init.lua` through `VIMINIT`
  (`VIMINIT='lua require("nix-info.init_main")'`). Removing the stale
  `~/.config/nvim` symlink therefore does not change how Neovim initializes; it
  only turns `stdpath("config")` into a real, writable directory.
- The tracked `dotfiles/config/nvim/lazy-lock.json` stays the pinned snapshot;
  it is not hand-edited to chase an update.

## Tasks

- [ ] T1 Branch and task document.
- [ ] T2 Pin `saghen/blink.cmp` to `version = "1.*"` with the reason in a
      comment.
- [ ] T3 Rebuild home-manager on gear5th and confirm the pin is materialized in
      the store tree.
- [ ] T4 Move the stale `~/.config/nvim` symlink aside and seed a writable
      runtime lockfile from the tracked copy.
- [ ] T5 Restore the six drifted plugins to the tracked pins and rebuild blink's
      Rust matcher.
- [ ] T6 Verify and close out.

## Verification evidence

- T2: file read-back of `lua/plugins/completion.lua`.
- T3: `home-manager switch --flake ~/nixos-conf#gear5th` exit status and the
  materialized `completion.lua` in the store tree.
- T4: `test -w ~/.config/nvim/lazy-lock.json`; `nvim-lock.sh check` exit status.
- T5: `git rev-parse HEAD` per plugin compared against the lockfile; blink's
  `target/release/libblink_cmp_fuzzy.so` present.
- T6: headless `require('blink.cmp')` returns true, `nvim --headless` leaves an
  empty `:messages`, and the drift audit reports zero drifted plugins.
