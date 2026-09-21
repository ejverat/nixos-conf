# Feature: own the Neovim plugin layer (drop LazyVim, keep lazy.nvim)

## Goal

`dotfiles/config/nvim` loads from a plugin specification written in this repo
instead of from the LazyVim distribution: one engine per function, lazy loading
by event/`ft`/`cmd`, and a lockfile that is the single source of truth. No
behavior regression for LSP, formatting, debugging, `oil`, `molten`/`image`,
the Unreal suite, CMake, dotnet, markdown and the agentic chat.

## Audit (2026-09-21, runtime-verified on chopper)

The current config is LazyVim 16.0.1 + lazy.nvim: 28 spec files, 76 plugins,
1.1 GB in `~/.local/share/nvim`. Findings that motivate this feature:

1. **Two completion engines, one of them dead.** `vim.g.lazyvim_cmp = "auto"`
   makes LazyVim's default-extras mechanism import `coding.blink`; that extra
   carries `{ "hrsh7th/nvim-cmp", optional = true, enabled = false }`, so
   `hrsh7th/nvim-cmp` is never installed (absent from `lazy-lock.json` and from
   `~/.local/share/nvim/lazy`). Dead code: `lua/plugins/nvim-cmp.lua` (92
   lines) and the nvim-cmp parts of `clangd.lua` and `lazydev.lua`.
   `snippets.lua` loads friendly-snippets into LuaSnip's store, which blink
   does not read. Blink's Rust matcher **is** built
   (`blink.cmp/target/release/libblink_cmp_fuzzy.so`).
2. **`clangd.lua` bypasses LazyVim**: `require("lspconfig").clangd.setup{}`
   inside the `opts` of `nvim-lspconfig` (deprecated API in nvim-lspconfig 3.x,
   which now feeds `vim.lsp.config`), skipping LazyVim's keys/capabilities.
3. **Everything loads at startup**: `defaults.lazy = false` -> 73 plugins per
   start. `--startuptime`: 196 ms total, `require('config.lazy')` 190 ms, with
   `dap` 38.9 ms, `image.nvim` 10.1 ms, `UNL.nvim` 8.8 ms, LuaSnip 7 ms.
4. **`editor = { telescope = true }` in `lua/config/lazy.lua` is not a
   lazy.nvim option** (`LazyConfig` has no `editor` key and lazy does not
   validate unknown root keys). The effective picker comes from
   `vim.g.lazyvim_picker = "telescope"` plus `origin = "global"` in
   `LazyVim.config.register_defaults`.
5. **Triple C#/dotnet stack**: `csharp.nvim` (omnisharp), `omnisharp.lua`
   (lspconfig) and `easy-dotnet.nvim`.
6. **Split lockfile**: lazy writes `stdpath("config")/lazy-lock.json`
   (`~/.config/nvim/lazy-lock.json`), while `dotfiles/config/nvim/lazy-lock.json`
   is the tracked copy. They already diverge (agentic.nvim `e9c64a2` runtime vs
   `81628c1` in git).
7. **Weight**: UNL.nvim 391 MB, snacks 34 MB, markview 26 MB.

## Decision

Drop the LazyVim distribution and keep lazy.nvim with a specification owned by
this repo. Rejected: **A** pruning inside LazyVim (its keys depend on
`Snacks.picker`/`LazyVim.pick`, so disabling plugins breaks the base layer, and
the distribution can still change defaults under us -- it already did once with
the completion engine); **C** moving plugins into `pkgs.vimPlugins` now (most of
the set is packaged, but `agentic.nvim`, `nvim-platformio.lua`, `csharp.nvim`,
`live-server.nvim` and `structlog.nvim` are not, and every plugin update would
become a system rebuild). C stays as a later, optional slice once this spec is
small; `vim.pack` in 0.12.5 still has no lockfile.

## Constraints carried over (do not regress)

- `performance.rtp.reset = false` and `performance.reset_packpath = false` stay:
  the wrapper (`modules/features/neovim.nix`) prepends
  `$HOME/.dotfiles/config/nvim` to the rtp and sources `init.lua` via `VIMINIT`
  while `stdpath("config")` remains `~/.config/nvim` (see
  `odd/tasks/neovim-lazy-rtp-fix.md`, merged as `bfc6cad`).
- `~/.dotfiles` is read-only store symlinks (`modules/features/dotfiles.nix`,
  `recursive = true`), so deploy = edit repo + `sudo nixos-rebuild switch
  --flake .#chopper`. Iterate on a `/tmp` copy with `nvim -u /tmp/cfg/init.lua`
  and deploy only after validating.
- Tree-sitter parsers come from the wrapper
  (`specs.treesitter-grammars`); Neovim 0.12 can highlight natively with
  `vim.treesitter.start()`.

## Proposed stack (pending user confirmation)

| Function | Proposal | Rationale |
| --- | --- | --- |
| Completion | `blink.cmp` only | Rust matcher already built; one engine |
| Snippets | blink's `snippets` source + friendly-snippets | LuaSnip only if custom snippet files are needed |
| Picker | `fzf-lua` | No plenary dependency; `rg`/`fd` are already on the wrapper PATH (telescope needs plenary, and its `fzf-native` sorter needs `make`, absent) |
| Explorer | `oil.nvim` | Already used, minimal |
| Statusline | `lualine.nvim` (or `mini.statusline` for the leaner variant) | Keeps current look |
| Editor niceties | `mini.ai`, `mini.pairs`, `mini.icons`, `gitsigns`, `which-key` | Small, single-purpose |
| Dropped | snacks, noice, trouble, flash, bufferline, persistence, todo-comments, dressing, ts-comments, tree-sitter-manager | Distribution layer, not user requirements |
| LSP | `vim.lsp.config` + `vim.lsp.enable` (0.12), `nvim-lspconfig` only as a server-config source | Removes `require("lspconfig").X.setup` (deprecated) |
| Treesitter | Parsers from the wrapper + `vim.treesitter.start()`; keep `nvim-treesitter-textobjects` only if `]f`/`]c` textobjects stay | Removes one plugin entirely |
| Lazy | `defaults.lazy = true` plus explicit event/`ft`/`cmd` per spec | Real lazy loading |

## Tasks

- [x] T1 Branch `feat/nvim-minimal` + this feature doc, and the
      architecture-independent pruning: delete `lua/plugins/example.lua`,
      delete the dead `lua/plugins/nvim-cmp.lua` and its nvim-cmp fragments in
      `clangd.lua`/`lazydev.lua`, remove `editor = { telescope = true }`.
      Done 2026-09-21: `git rm` of the two files plus edits to `lazy.lua`
      (-1 line), `clangd.lua` (-14) and `lazydev.lua` (net -11; the file kept
      only the blink source). Static evidence: `loadfile()` under
      `nvim --clean --headless` compiles every `lua/config/*.lua`,
      `lua/plugins/*.lua` and `init.lua` with no syntax error, and no spec
      references `hrsh7th/nvim-cmp` any more. Runtime evidence after the user's
      `sudo nixos-rebuild switch --flake .#chopper` (materialized store path
      `s0lilxanlaapjp3x5y9dcksg5n09m121-hm_nvim`): `~/.dotfiles/config/nvim/lua/plugins`
      holds 26 files with `example.lua`/`nvim-cmp.lua` gone, `lua/config/lazy.lua`
      has no `editor` key, `nvim --headless` starts with an empty `:messages`,
      `lazy.core.config.plugins` = 73 (same as baseline) and startup measured
      131-151 ms across three runs vs the 196 ms single-run baseline.
- [x] T2 Bootstrap without LazyVim: rewrite `init.lua`,
      `lua/config/{options,keymaps,autocmds,lazy}.lua` and land the minimal base
      spec. Done 2026-09-21: `init.lua` now requires options/lazy/autocmds/
      keymaps explicitly (LazyVim used to do that); `lua/config/lazy.lua` no
      longer imports `lazyvim.plugins`; new specs `ui.lua`, `picker.lua`
      (fzf-lua), `completion.lua` (blink) and `lsp.lua` (native
      `vim.lsp.config` + `vim.lsp.enable`); `formatting.lua` carries the
      format-on-save/lint triggers LazyVim used to wire; `dap.lua`,
      `refactoring.lua`, `clangd.lua`, `treesitter.lua`, `omnisharp.lua` and
      `markdown.lua` were rewritten off the LazyVim API; `nix.lua`,
      `typescript.lua`, `tailwindcss.lua` and `texlab.lua` (LazyVim-only
      `opts.servers` schemas) were folded into `lsp.lua`/`markdown.lua`;
      `snippets.lua` was dropped. `modules/features/neovim.nix` adds
      `pkgs.ripgrep` and `pkgs.fzf` to `neovimExtraPkgs` so the picker does not
      depend on the ambient PATH.
      Evidence: 25 spec files, every spec resolved, 60 plugins, no Lua error in
      `:messages`, and a module smoke test (dap, dapui, fzf-lua, blink.cmp,
      conform, lint, gitsigns, oil, toggleterm, mini.*, which-key, lualine,
      clangd_extensions, refactoring, nvim-treesitter[-textobjects], markview,
      lazydev, tokyonight, lspconfig) loading clean.
- [ ] T3 LSP migration: `vim.lsp.config`/`vim.lsp.enable` for nixd, ts_ls,
      tailwindcss, texlab, clangd (+ the clangd arguments currently hardcoded in
      `clangd.lua`), and consolidation of the C#/dotnet stack to one plugin.
      Also decide the fate of `p00f/clangd_extensions.nvim`: it declares
      `lazy = true` with no event/`ft`/`cmd` and `config = function() end`, so
      it never loads and its `:ClangdSwitchSourceHeader` command (bound to
      `<leader>ch` in the same file) is dead today.
      Evidence: server attaches per filetype, keymaps work, no `lspconfig`
      deprecation warnings.
- [ ] T4 Completion and snippets: blink only, friendly-snippets wired through
      blink's own source (plus `lazydev` integration for `lua`). Evidence:
      completion on lua/c/cpp/ts, snippet expansion, lazydev modules resolved.
- [ ] T5 Deferred loading for the heavy stacks: `dap` (cmd/keys),
      `image.nvim` + `molten` (`ft = python`), Unreal suite (`ft = {c,cpp}`,
      `cmd = UDEV`), `cmake-tools` (`ft = cmake`), `platformio` (keep `cond`),
      `markdown-preview` (`cmd`). Evidence: startup drops, each stack still
      opens on demand.
- [ ] T6 Lockfile policy + docs: single source of truth for
      `lazy-lock.json`, documented update flow (runtime -> repo), and a short
      `docs/` note or README section for the new layout. Evidence: lockfile
      identical in both locations after an update cycle.
- [ ] T7 Close-out: final `--startuptime` and plugin count comparison against
      the baseline, feature doc updated, memory recorded.

## Deviations from the proposed stack (recorded, revisable)

- `telescope.nvim` stays installed but only as a dependency of
  `easy-dotnet.nvim` and `nvim-platformio.lua`, which call telescope APIs
  internally. The user-facing picker is fzf-lua. T3/T5 decide the fate of those
  two plugins, and telescope leaves with them.
- `nvim-treesitter` is kept (main branch): highlighting, indent and folds now
  come from a native `FileType` autocmd calling `vim.treesitter.start`,
  `nvim-treesitter.indentexpr` and `vim.treesitter.foldexpr`, and
  `nvim-treesitter-textobjects` still needs it for the `]f`/`]c`/`]a`
  textobjects. Dropping the plugin entirely is a T5 experiment.
- `nvim-web-devicons` stays as an `oil.nvim` dependency next to `mini.icons`.
- `markview.nvim` moved from the deleted `texlab.lua` into `markdown.lua`.
- The keymap layer is a **curated** port of the LazyVim defaults, not a
  byte-for-byte copy: search (`<Esc>`, `n`/`N` centered, visual `p`), windows
  (`<C-hjkl>`, `<leader>-`, `<leader>|`, `<leader>wd`, resize with `<C-Arrows>`),
  buffers (`<S-h>`/`<S-l>`, `<leader>bb/bd/bo`), files and config (`<leader>fn`,
  `<leader>qq`, `<leader>l`, `<leader>ur`), toggles (`<leader>us/uw/ul/uf/uh/ud`),
  line moves (`<A-j>`/`<A-k>`), centered scrolling (`<C-d>`/`<C-u>`), terminal
  (`<C-/>`, `<leader>ft`, term `<Esc><Esc>`) and format (`<leader>cf`).
- LSP keymaps are registered on `LspAttach` in `autocmds.lua`: `gd`, `gD`, `gr`,
  `gI`, `gy`, `K`, insert `<C-k>`, `<leader>ca/cr/cd`, `[d`/`]d` plus native
  inlay hints.

## Findings surfaced while implementing T2

- LazyVim silently loaded `lua/config/{options,keymaps,autocmds}.lua`; the new
  bootstrap must require them explicitly or they never run.
- `vim.o` rejects dict/array values and string methods: `fillchars`,
  `listchars` and `sessionoptions` need `vim.opt`, and `shortmess:append` needs
  `vim.opt.shortmess`. Both bugs were caught by the sandbox smoke test.
- The installed `clangd_extensions.nvim` has no inlay-hint feature at all, so
  the `inlay_hints` opts this config carried were dead; hints come from
  `vim.lsp.inlay_hint`. `<leader>ch` works now (the spec loads on `ft`/`keys`).
- `refactoring.lua` referenced an undefined global `pick` and declared
  `<leader>rf`/`<leader>rp` twice; it now uses `select_refactor()` with one
  binding per action.

## Verification evidence

(filled in as tasks close)

- Baseline before this feature: 196 ms startup, `require('config.lazy')`
  190 ms, 73 plugins, 76 locked plugins, 1.1 GB store.
- T1 static: `loadfile()` over all 27 remaining spec files + `init.lua` +
  `lua/config/*.lua` -> no syntax errors; `git diff --stat` = 4 files,
  -27/+3 lines; no remaining `hrsh7th/nvim-cmp` spec.
- T1 runtime: pending deploy (`sudo nixos-rebuild switch --flake .#chopper`),
  then `:messages` must be free of errors and startup unchanged (~196 ms).
  Done 2026-09-21: deploy confirmed by the user; materialized tree
  `s0lilxanlaapjp3x5y9dcksg5n09m121-hm_nvim`, 26 spec files, `:messages` empty,
  73 specs, startup 151/149/131 ms (three runs). The 196 ms baseline was a
  single pre-deploy run and is not isolated from cache effects; T7 compares
  both stacks with the same methodology.
- T2 static/sandbox (before deploy): `loadfile()` over every Lua file passes;
  the config was loaded end to end with the raw nvim 0.12.5 binary in an
  isolated `NVIM_APPNAME=nvim-t2` profile (plugin dir symlinked to the real
  one): every spec resolved, 60 plugins, `:messages` with zero error lines, all
  core mappings present (`,ff`, `<Esc>`, `<C-h>`, `,cf`, `<A-j>`, `<C-/>`),
  autocmd groups registered (`config` 18, `LspAttach` 2, `config_treesitter` 1)
  and the module smoke test clean. `nix eval .#packages.x86_64-linux.myNeovim.drvPath`
  resolves with the new `fzf`/`ripgrep` entries.
- T2 runtime: pending the next deploy; verify `:messages`, LSP attach per
  filetype, picker keys, format on save, and compare startup.
