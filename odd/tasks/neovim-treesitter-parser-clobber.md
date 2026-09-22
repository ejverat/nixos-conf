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

- [ ] T1 Branch `fix/nvim-plugin-layer-drift` and this document.
- [ ] T2 Drop the `build = ":TSUpdate"` hook from the `nvim-treesitter` spec and
      document the parser-ownership rule in the spec comment.
- [ ] T3 Rebuild home-manager on gear5th.
- [ ] T4 Reinstall the Unreal-patched cpp parser into `site/parser`.
- [ ] T5 Verify and close out.

## Verification evidence

- T2: file read-back of `lua/plugins/treesitter.lua`.
- T3: `home-manager switch --flake ~/nixos-conf#gear5th` exit status and the
  materialized spec in the store tree.
- T4: `site/parser-info/cpp.revision` no longer the stock revision; the
  `(unreal_body_macro) @x` query parses.
- T5: highlighter attached on a real `.cpp`, the exact fzf-lua call
  (`pcall(vim.treesitter.start, bufnr, 'cpp')`) returns true, empty
  `:messages`, and the spec's pinned commit for the map unchanged.
