# Feature: stop nvim-treesitter's build hook from clobbering the Unreal cpp parser

## Goal

Cpp/c buffers get working tree-sitter highlighting again and the fzf-lua preview
stops reporting `unable to attach treesitter highlighter for filetype 'cpp' ...
Invalid node type "unreal_body_macro"`. The Unreal macros
(`GENERATED_BODY()`, `UCLASS`, `UPROPERTY`, ...) keep their captures, and no
`:Lazy update` can silently replace the patched grammar with the stock one.

## Root cause (validated 2026-09-22 on gear5th)

Two owners wrote to one directory.

1. `lua/plugins/treesitter.lua` prepends `stdpath("data")/site` to the
   runtimepath so the Unreal-patched grammars win, and
   `tree-sitter-manager.nvim` (configured in `lua/plugins/unreal.lua` with
   `languages.cpp.install_info.url = https://github.com/taku25/tree-sitter-cpp`)
   installs them into `stdpath("data")/site/parser`.
   `USX.nvim/after/queries/cpp/highlights.scm` uses the extra node types that
   only that fork defines (`unreal_body_macro`, `uclass_macro`,
   `unreal_argument_list`, `unreal_api_specifier`, `unreal_specifier*`).
2. The same spec gave `nvim-treesitter` a `build = ":TSUpdate"` hook, and
   `:TSUpdate` rebuilds **every parser nvim-treesitter knows** from its own
   pinned stock sources into that same `stdpath("data")/site/parser`.

During the 2026-09-22 `:Lazy update` (the same one that moved the six plugin
checkouts in `odd/tasks/neovim-blink-pin.md`) the hook ran and replaced
`site/parser/cpp.so` with the stock grammar:

| evidence | value |
| --- | --- |
| `site/parser-info/cpp.revision` | `c009222808634c1014f82438d4883753516a2c24` |
| that revision is | HEAD of `tree-sitter/tree-sitter-cpp` (stock grammar) |
| and is also | the cpp revision pinned in `nvim-treesitter/lua/nvim-treesitter/parsers.lua` |
| `taku25/tree-sitter-cpp` HEAD | `920e9810cc64a47fa05cfcf30c7caecb85b5f2c3` |
| mtime of `site/parser/cpp.so` | 2026-09-22 02:11 (the update); `ushader`/`verse` stayed at 2026-09-18 12:32 because they are not in nvim-treesitter's registry |

Direct proof that the loaded language lacks the node type:

```
vim.treesitter.query.parse('cpp', '(unreal_body_macro) @x')
  -> Query error at 1:2. Invalid node type "unreal_body_macro"
```

The merged `cpp` highlights query is built, in runtimepath order, from
`nvim-treesitter/runtime/queries/cpp` (prepended by the config),
`site/queries/cpp` (the fork's own set, `; inherits: c`) and
`USX.nvim/after/queries/cpp` (`;; extends`, the Unreal patterns). The last file
is what breaks, and the reported error at `960:2` is the tail of that merge.

**Silent half of the bug:** the FileType autocmd in `treesitter.lua` wraps
`vim.treesitter.start` in `pcall` and returns on failure, so cpp/c buffers were
simply left without tree-sitter highlighting
(`vim.treesitter.highlighter.active[buf] == nil`). fzf-lua is the only reporter,
because its previewer attaches the highlighter outside that `pcall`
(`fzf-lua/previewer/builtin.lua`, `ts_attach`).

## Decision

Remove the `build = ":TSUpdate"` hook and keep the patched parser.

- **A (chosen) — no automatic `:TSUpdate`, reinstall the fork.** Parser
  ownership becomes single: the Nix wrapper pack provides the stock grammars,
  `tree-sitter-manager.nvim` owns `site/parser` for the Unreal extras. The hook
  was redundant as well: the wrapper pack already ships 320 stock grammars
  (`nvim-packdir/pack/myNeovimPackages/start/COLLATED_TS_GRAMMARS`, which
  includes `c` and `cpp`). Manual updates stay safe because after a cpp/c buffer
  loads, tree-sitter-manager's own `:TSUpdate` is the active one and it installs
  cpp from `taku25`.
- **B (rejected) — give tree-sitter-manager a separate `parser_dir` prepended
  before `site`.** Robust against future clobbering, but it adds a second
  managed directory and query-dir coupling to keep in sync for a hook this
  config does not need.
- **C (rejected) — keep the stock parser and drop the Unreal queries.** Loses
  `GENERATED_BODY`/`UCLASS`/`UPROPERTY` captures and the filetype detection
  wiring USX.nvim owns, to save one spec line.

## Constraints carried over (do not regress)

- `site` stays prepended: without it the stock `cpp` from
  `nvim-treesitter/parser` or the Nix pack resolves first and the Unreal queries
  cannot build.
- `nvim-treesitter/runtime` stays prepended for the upstream query set.
- The Unreal patched grammar is `taku25/tree-sitter-cpp` only;
  `taku25/tree-sitter-c` does not exist. `c` is pulled in as cpp's dependency
  (`requires = { "c" }`) and stays stock.

## Tasks

- [x] T1 Branch and this document. Done 2026-09-22; the branch was renamed to
      `fix/nvim-plugin-layer-drift` because it now carries both plugin-layer
      repairs (this one and `odd/tasks/neovim-blink-pin.md`).
- [x] T2 Drop the `build = ":TSUpdate"` hook from the `nvim-treesitter` spec and
      document the parser-ownership rule. Done 2026-09-22, commit `93ad550`.
- [x] T3 Rebuild home-manager on gear5th. Done 2026-09-22.
- [x] T4 Reinstall the Unreal-patched cpp parser into `site/parser`. Done
      2026-09-22.
- [x] T5 Verify and close out. Done 2026-09-22.

## Verification evidence

- T2: read-back of `dotfiles/config/nvim/lua/plugins/treesitter.lua`;
  `grep -nE '^[[:space:]]*build = '` finds no option (only the comment that
  explains why there is none).
- T3: `~/.nix-profile/bin/home-manager switch --flake ~/nixos-conf#gear5th`
  exited 0 with no activation error, and the materialized
  `/nix/store/lipb2h7hnvmrady6xh4i23009clxxkll-hm_nvim/lua/plugins/treesitter.lua`
  has no `build` option either.
- T4: in the real wrapper, after asserting the configured source is the fork
  (`=== cpp repo: https://github.com/taku25/tree-sitter-cpp`), the update ran
  (`Updating cpp` -> `Building cpp`) and produced
  `site/parser/cpp.so` = 9 189 400 bytes, 2026-09-22 02:44. The fork's own query
  set replaced `site/queries/cpp` (`highlights.scm` 1 018 bytes starting at
  `; Functions`, i.e. **without** `; inherits: c`) -- the state the spec comment
  describes, where the inherit comes from the prepended
  `nvim-treesitter/runtime/queries/cpp`. `site/queries/c` was left alone because
  tree-sitter-manager skipped the already-installed stock `c` dependency.
  The decisive check: `vim.treesitter.query.parse('cpp', '(unreal_body_macro) @x')`
  now parses (it used to fail with `Invalid node type`).
- T5: `nvim --headless probe_ue.cpp "+luafile /tmp/verify_cpp.lua"` on a
  UE-shaped `.cpp` (`UCLASS()`, `class ... : public AActor`, `GENERATED_BODY()`):
  `filetype=cpp`, `fzf-lua ts_attach ok=true` (the exact
  `pcall(vim.treesitter.start, bufnr, 'cpp')` from
  `fzf-lua/previewer/builtin.lua`), `highlighter attached=true`,
  `highlights query builds=true`, `total captures=28`,
  `function.macro captures=GENERATED_BODY`, and an empty `:messages`. Same shape
  for the stock path (`probe_c.c`): `c ts start ok=true`,
  `c highlighter attached=true`, `c highlights query builds=true`. Plain
  `nvim --headless` startup leaves an empty `:messages`, and
  `scripts/nvim-lock.sh check` still reports `in sync (56 entries)`.

## Known residue (deliberate)

`site/parser-info/cpp.revision` still records the stock
`c009222808634c1014f82438d4883753516a2c24` while the installed parser is
`taku25/tree-sitter-cpp` HEAD (`920e9810cc64a47fa05cfcf30c7caecb85b5f2c3`). It is
left in place on purpose: `nvim-treesitter`'s `needs_update()`
(`lua/nvim-treesitter/install.lua`) compares that file with its own pinned
revision and returns false while they match, so a stray nvim-treesitter
`:TSUpdate` skips cpp instead of rebuilding it from the stock source. Nothing in
the parser load path reads it.

## Close-out

The fzf-lua warning is gone, cpp/c highlighting is actually attached again, and
no automatic update path replaces the patched grammar any more.

Left undone on purpose:

- No push and no PR: delivery stays a human decision.
- `c` stays stock: `taku25/tree-sitter-c` does not exist, so only cpp is patched
  by the fork and `c` is pulled in as its dependency.
- The 31 stock parsers nvim-treesitter left in `site/parser` are untouched. They
  shadow the Nix pack with nvim-treesitter's pinned revisions, which matches the
  upstream query set this spec prepends; deduplicating them is a separate
  cleanup with its own grammar/query version-skew risk.
