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
      `refactoring.lua`, `clangd.lua`, `treesitter.lua` and
      `markdown.lua` were rewritten off the LazyVim API; `omnisharp.lua` was
      folded into `lsp.lua` and deleted; `nix.lua`,
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
- [x] T3 LSP consolidation. Done 2026-09-21:
      * native LSP is already the only path (`vim.lsp.config` + `vim.lsp.enable`
        in `lsp.lua`; no `require("lspconfig")` anywhere);
      * **C# is one stack**: `pkgs.omnisharp-roslyn` on the wrapper PATH plus
        `vim.lsp.config("omnisharp", { settings = ..., on_attach = ... })`.
        `csharp.nvim` is deleted: it started OmniSharp through its own
        `vim.lsp.start{}` (`lua/csharp/modules/lsp/omnisharp.lua:68`), so the
        semantic-token workaround this config carried was never applied. The
        settings mirror what csharp.nvim used to pass as command flags
        (FormattingOptions, RoslynExtensionsOptions, Sdk, MsBuild).
      * `easy-dotnet.nvim` stays as the .NET tooling with `picker = "fzf"` and
        `lsp.enabled = false` (one server per buffer, no second server
        downloaded at startup). Its dap registration is kept; C# debugging uses
        its own global `EasyDotnet` dotnet tool, which mason never provided.
      * **mason is gone**: OmniSharp and codelldb now come from nixpkgs
        (`pkgs.omnisharp-roslyn`, and a four-line wrapper around
        `vscode-extensions.vadimcn.vscode-lldb` that exposes
        `$out/bin/codelldb`). `clangd.lua`, `cmake-tools.lua`, `dap.lua` and
        `rust.lua` dropped their mason references; `rust.lua` derives liblldb
        from the resolved adapter path.
      * **telescope is gone**: `easy-dotnet` uses fzf-lua and `platformio` uses
        `picker_backend = "ui_select"`, which were the only two remaining
        consumers.
      * `p00f/clangd_extensions.nvim` is kept: `<leader>ch` no longer needs it
        (it issues `textDocument/switchSourceHeader` itself), and it loads on
        `ft`/`keys` for `:ClangdAST`, type hierarchy and symbol info.
      Evidence: `nix build .#packages.x86_64-linux.myNeovim` succeeds with the
      new wrapper; in the sandbox the spec set is 55 plugins (from 60) with no
      mason/telescope/csharp entry, `vim.lsp.is_enabled("omnisharp")` is true
      and the adapter resolves to the store `OmniSharp`; end to end on a .NET
      project OmniSharp attaches with the project root, reports 65 token types
      with zero spaces (the on_attach fix actually running now) and semantic
      tokens are active; `dap.adapters` holds only `codelldb` and
      `easy-dotnet`. Runtime follow-up after the user's confirmation: `gd`
      works on `Program.cs`, and the one inline error it showed
      (`CS0103`, missing `using System;`) was a fixture bug, not a config one:
      removing the `using` reproduces it and restoring it clears the buffer to
      zero diagnostics, which proves OmniSharp diagnostics reach
      `vim.diagnostic`.
- [x] T4 Completion and snippets. Done 2026-09-21: blink.cmp is the only
      engine (LuaSnip is gone from the spec set and from disk; the only mention
      left is a comment), friendly-snippets reaches it through blink's own
      `snippets` source with `preset = "default"` (the `vim.snippet` engine),
      and the `lazydev` provider is wired for `lua` via
      `sources.per_filetype.lua`. Added `build = "cargo build --release"`:
      blink's Rust matcher lives in `target/release`, which is gitignored
      upstream, so a fresh clone would silently fall back to the Lua matcher.
      Evidence: `blink.cmp.fuzzy.rust` loads (Rust matcher, not the fallback);
      providers are `buffer,cmdline,lazydev,lsp,omni,path,snippets` with
      defaults `lsp,path,snippets,buffer` and `per_filetype.lua = { lazydev }`;
      `lazydev.integrations.blink` loads; the runtimepath exposes 143
      friendly-snippets JSON files (57 at the top level, the rest nested per
      filetype, e.g. `snippets/lua/`); expanding a real friendly-snippets body
      through `vim.snippet` produces the expected text and placeholder jumps
      work; `:messages` is clean. The interactive menu itself (type a prefix in
      insert mode, `<C-y>` to accept, `<C-l>`/`<C-h>` to move between snippet
      placeholders, `<C-n>`/`<C-p>` to pick) is the user-facing check; the
      placeholder jumps were verified end to end in a real `tmux` session
      (`send-keys`, cursor 10 -> 14 -> 17 forward and back with `<C-h>`), which
      is also what exposed the fold bug recorded below.
- [x] T5 Deferred loading. Done 2026-09-21. Measured first (`--startuptime` plus
      an eager-plugin census), then deferred what actually cost: the dap chain
      (`require('dap')` 9.6 ms + `dapui` 2.0) and `fzf-lua` (5.4 ms) were only
      loaded because `easy-dotnet`'s setup registers a dap adapter and validates
      its picker; `image.nvim` + `molten` cost ~7 ms (`image/utils/tmux` alone
      4.9 ms); `UNL.nvim` ~5 ms; `nvim-ts-autotag` 2.8 ms.
      Triggers now: `easy-dotnet` (`ft = cs`, `cmd = Dotnet`), `molten` +
      `image.nvim` (`ft = python`), `UNL.nvim` (rides with UnrealDev on `ft`/
      `cmd`), `tree-sitter-manager` (`ft = cpp,c,ushader,verse`), `rustaceanvim`
      (`ft = rust`, `cmd = RustLsp`), `markview` (`ft = markdown*`),
      `nvim-ts-autotag` (`ft` = markup/jsx set), `neogen` (`cmd`), `colortils`
      (`cmd`), `oil` (`cmd = Oil` + `keys` for `-`, with its setup moved to
      `opts` so the keymap exists before the plugin loads), `toggleterm` (`cmd`).
      `USX.nvim` stays eager **on purpose**: its `after/queries/cpp` files must be
      on the runtimepath when the highlighter attaches, which happens on
      FileType, too late for a lazy load to add them. `platformio` (`cond`),
      `cmake-tools` (`keys`) and `markdown-preview` (`cmd`) were already deferred
      in T2.
      Evidence: eager plugins 25 -> 6 (`USX.nvim`, `lazy.nvim`, `mini.icons`,
      `nvim-lspconfig`, `nvim-treesitter`, `tokyonight.nvim`, all deliberate);
      startup 90 -> **32.2 / 32.4 / 33.4 ms** across three runs (196 ms was the
      original LazyVim baseline). On-demand matrix verified in the sandbox: a
      `.cs` loads easy-dotnet + nvim-dap + plenary, a `.py` loads molten +
      image, a `.cpp` loads UnrealDev + UNL + tree-sitter-manager, a `.rs` loads
      rustaceanvim, a `.md` loads markview + autotag, `:Oil` loads oil and the
      `<C-/>` mapping loads toggleterm; the `:Dotnet`, `:Oil`, `:Neogen`,
      `:Colortils` and `:ToggleTerm` stubs all exist before loading.
- [x] T6 Lockfile policy and layout docs. Done 2026-09-21. lazy.nvim writes
      `stdpath("config")/lazy-lock.json` = `~/.config/nvim/lazy-lock.json` (its
      default), which cannot be this repository because the config directory is
      read-only from the store. The tracked `dotfiles/config/nvim/lazy-lock.json`
      is the pinned snapshot, and `scripts/nvim-lock.sh` bridges them:
      `sync` (runtime -> repo, after `:Lazy update`), `seed` (repo -> runtime,
      before `:Lazy restore` on a fresh machine, with a `.bak` when they differ)
      and `check` (sorted comparison, exit 1 on drift).
      Also cleaned up and documented: `lazyvim.json` (LazyVim's state file) and
      `.neoconf.json` (neoconf is not installed) are gone, `.gitignore` is down
      to editor noise, and `README.md` now documents the layout (entry point,
      the read-only config vs writable `~/.config/nvim` split, the two rtp
      switches the wrapper needs, Nix-provided servers vs lazy-provided plugins),
      the lockfile policy and the fixtures.
      Evidence: the tracked lockfile was 76 entries of the LazyVim era and is now
      the 56 entries that actually run (no `LazyVim`, `bufferline`, `catppuccin`,
      `csharp.nvim`, `dressing`, `flash`, `snacks`, `telescope`, `mason`);
      `check` reports `in sync (56 entries)` and exits 0; `seed` is a no-op when
      both copies match (no backup written); no arguments prints the usage and
      exits 2. `~/.config/nvim/lazyvim.json` remains in the writable state
      directory and nothing reads it any more.
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
- **lazy.nvim merges duplicate plugin specs and the last `config` wins.**
  `lsp.lua` and `omnisharp.lua` both declared `neovim/nvim-lspconfig` with a
  `config` function; `omnisharp.lua` sorts later, so it replaced the LSP setup
  and the deployed T2 started with `vim.lsp.is_enabled("clangd") == false`:
  every server was silently disabled. Fixed by making `lsp.lua` the only owner
  of that spec (the omnisharp workaround moved into it) and deleting
  `omnisharp.lua`. Same hazard applies to any future spec that touches
  `neovim/nvim-lspconfig`; the rule is documented at the top of `lsp.lua`.
  `opts` functions do merge across specs (verified with the nvim-dap codelldb
  adapter from `clangd.lua`), only `config` is last-wins.
- **cpp tree-sitter highlighting was silently dead before this feature, and
  stayed half-dead after the parser fix.** `USX.nvim` ships
  `after/queries/cpp/highlights.scm` using Unreal node types
  (`unreal_body_macro`) that only exist in the Unreal-patched parsers installed
  under `~/.local/share/nvim/site/parser` (cpp, c, ushader, verse). The Nix
  wrapper's stock grammars were earlier on the runtimepath, so
  `vim.treesitter.query.get("cpp", "highlights")` returned nil and LazyVim's
  `LazyVim.treesitter.have(ft, "highlights")` guard skipped
  `vim.treesitter.start` for cpp entirely: no error, no highlighting. The new
  unconditional `pcall(vim.treesitter.start)` exposed it as a hard error
  (surfaced by fzf-lua previews).
  Two runtimepath prepends are needed, in `treesitter.lua`:
  1. `stdpath("data")/site` so the Unreal parsers win over the wrapper's stock
     grammars (otherwise the query cannot be built at all);
  2. `<nvim-treesitter>/runtime` because the Unreal stack also installs its own
     fork of the `cpp`/`c` queries into `site/queries`, and that fork **has no
     `; inherits: c` line** -- which is where cpp keywords, types and
     preprocessor captures come from. Only then does the merged query produce
     captures; before that the highlighter attached and painted nothing, so cpp
     looked like it had "partial" highlighting from LSP semantic tokens alone.
- `vim.o` rejects dict/array values and string methods: `fillchars`,
  `listchars` and `sessionoptions` need `vim.opt`, and `shortmess:append` needs
  `vim.opt.shortmess`. Both bugs were caught by the sandbox smoke test.
- The installed `clangd_extensions.nvim` has no inlay-hint feature at all, so
  the `inlay_hints` opts this config carried were dead; hints come from
  `vim.lsp.inlay_hint`. `<leader>ch` works now (the spec loads on `ft`/`keys`).
- `<leader>ch` was rewritten instead of relying on `:ClangdSwitchSourceHeader`.
  `textDocument/switchSourceHeader` is asymmetric: **source -> header** follows
  the `#include` graph and works with no index, while **header -> source** needs
  clangd's index (a header cannot know which translation units include it).
  Without `compile_commands.json` the background index has nothing to index, so
  clangd only knows the buffers opened in the session -- which is why the switch
  appeared to work only when both files were open, and otherwise answered null
  ("Corresponding file cannot be determined"). Measured on the fixture with a
  direct LSP request: source -> header resolves in both cases;
  header -> source resolves with `compile_commands.json` and returns null
  without it. The keymap now reports each failure mode explicitly (no clangd
  client attached / no counterpart found, with the index hint).
- `pkgs.cmake` joined `neovimExtraPkgs`: `cmake-tools.nvim` was configured but
  could never run, and CMake is also how `compile_commands.json` gets generated
  for C++ projects (the fixture ships a hand-written one; make-based projects
  can use `bear`/`compiledb`).

- **Tree-sitter folds silently broke snippet placeholder jumps.** The
  `FileType` autocmd set `foldmethod=expr` + `foldexpr` with the default
  `foldlevel=0`, so every fold is closed the moment it appears. A cursor jump
  into a closed fold is a no-op (`foldopen` does not include jumps), so
  `vim.snippet.jump` did nothing on any multi-line snippet -- and the same
  would happen to any other jump into a folded region (a `gd` into a folded
  function, for example). `treesitter.lua` now sets `foldlevel = 99`: folds
  still exist and `zc`/`zM`/`zR` work, but nothing starts hidden. This predates
  the feature (LazyVim enabled the same folds) and was invisible to the headless
  sandbox, where folds are never computed: it took a real `tmux` session driven
  with `send-keys` to see the `+--  3 lines` fold and the SELECT mode.
- **`<C-l>`/`<C-h>` never reach Neovim in this setup: WezTerm owns them.**
  `wezterm.lua` binds `CTRL+h/j/k/l` through `split_nav("resize", ...)` to
  resize panes, and its pass-through branch depends on `is_vim(pane)`, which
  reads an `IS_NVIM` user var that nothing in the config sets (the comment says
  "set by the plugin", but no plugin is loaded). So the terminal keeps the key
  and Neovim never sees it -- the same is true for the `<C-h/j/k/l>` *window*
  navigation this config inherited from LazyVim. `tmux` is not involved: its
  root table only binds them in copy-mode.
  The working pair is therefore `<Tab>`/`<S-Tab>` (and `<C-i>` **is** `<Tab>`,
  which is what the user discovered): blink's preset binds them to
  `snippet_forward`/`snippet_backward` while its menu is open, and
  `lua/config/keymaps.lua` now also maps them natively so they work with the
  menu closed, falling back to indent/dedent otherwise. Verified in a real tmux
  session: `<Tab>` walks 10 -> 14 -> 17 and `<S-Tab>` returns 17 -> 14 -> 10,
  while `<Tab>` on a plain line still inserts the indent.
- **WezTerm pass-through wired (option 2).** `wezterm.lua`'s `split_nav()`
  forwards `CTRL+h/j/k/l` when `is_vim(pane)` is true, which reads the `IS_NVIM`
  user var. This version of WezTerm has no `wezterm cli set-user-var`, so
  `lua/config/autocmds.lua` emits the OSC 1337 `SetUserVar` escape on `VimEnter`
  (`true`, scheduled so the TUI is up) and `VimLeavePre` (`false`), wrapped in
  tmux's DCS passthrough when `$TMUX` is set. tmux 3.7 already defaults
  `allow-passthrough` to on, so no tmux change was needed. The block is a no-op
  without `$WEZTERM_PANE`, which keeps the config portable.
  Verified by capturing the pane's raw output (`tmux pipe-pane` + `strings`):
  `SetUserVar=IS_NVIM=dHJ1ZQ==` ("true") after startup and
  `SetUserVar=IS_NVIM=ZmFsc2U=` ("false") after `:qa`, both inside `Ptmux;`.
  Trade-off to remember: while Neovim has focus, both `CTRL+h/j/k/l` and
  `META+h/j/k/l` reach Neovim, so WezTerm's pane resize/move bindings only apply
  when Neovim is not focused.
- **lazy.nvim validates `cmd` names: they must start with an uppercase letter.**
  `T5` shipped `cmd = { "RustLsp", "rustaceanvim" }` and the lowercase entry made
  lazy fail with `Invalid command name (must start with uppercase)` at startup,
  which also aborted that plugin's handlers. Auditing every `cmd` declaration
  against the commands the plugins actually define found two more wrong names
  from earlier slices: `ColortilsContinueNamedColor` (colortils only defines
  `Colortils`) and platformio's `Piocmd`/`Piodb` (the real ones are `Piocmdf`,
  `Piocmdh`, `PioLSP`, `PioTermList`, `Piolsserial`). `:RustLsp` is correct but
  only exists after rust-analyzer attaches, which the plugin documents, so
  `ft = rust` is the trigger that matters. Platformio's own commands only exist
  once its `cond` is true (or through its `:Pioinit` flow), so the list is inert
  in the common case: the forced-load audit shows them absent, which is expected
  rather than broken.
- The mini.nvim modules moved to the `nvim-mini` org. `T2` wrote the older
  `echasnovski/mini.*` URLs, which still redirect to the same commits but make
  lazy.nvim report `Origin has changed` (three entries) and refuse to update
  them. The specs now use `nvim-mini/mini.*`, and a cross-check of every spec
  URL against each installed plugin's `remote.origin.url` reports no other
  mismatch.
- `:Lazy clean` after T3 removed 20 plugin directories (76 -> 56) including
  LazyVim itself. The mason *data* directory (`~/.local/share/nvim/mason`) is
  not a lazy plugin and survives; nothing references it any more.

## Test fixtures

`~/Projects/cpp-smoke` (C++20: clangd, tree-sitter, textobjects, codelldb) and
`~/Projects/csharp-smoke` (a minimal .csproj + `Program.cs` for OmniSharp). Both
are outside this repo on purpose.

The C# fixture deliberately has no `ImplicitUsings`, so it needs an explicit
`using System;`: removing it reproduces `CS0103` ("The name 'Console' does not
exist in the current context") and adding it back leaves zero diagnostics,
which is the end-to-end proof that OmniSharp diagnostics reach
`vim.diagnostic` (that is how the missing `using` was first noticed).

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
- T2 runtime (partial, on the deployed config): the first deploy shipped two
  defects that were then fixed and re-verified in the sandbox:
  (a) no LSP server started (`vim.lsp.is_enabled("clangd") == false`) because of
  the duplicate `config` merge; after the fix `is_enabled` is true for clangd
  and nixd, `vim.lsp.config.clangd.cmd` carries the full argument list and
  `vim.lsp.config["*"]` carries the capabilities;
  (b) cpp highlighting failed (`pcall(vim.treesitter.start)` false, query build
  error). After the fix the runtimepath resolves two cpp parsers with
  `~/.local/share/nvim/site/parser/cpp.so` first, `vim.treesitter.query.get("cpp",
  "highlights")` is non-nil and `vim.treesitter.start` succeeds.
  End-to-end attach check with the wrapper PATH on `~/Projects/cpp-smoke`:
  `clients=1`, `clangd root=/home/ejverat/Projects/cpp-smoke`, zero diagnostics,
  `vim.lsp.buf.hover` callable.
- T2 runtime (highlighting): both defects above were found by measuring captures
  instead of trusting the absence of errors. Same-methodology comparison on
  `~/Projects/cpp-smoke/src/main.cpp` with the parsed tree as the source: the
  query built from the Unreal fork files alone (`site/queries/cpp` + USX)
  yields **0 captures**, while the merged query after the fix yields **135**
  (`#include` -> `keyword.import`, `static` -> `keyword.modifier`, `int` ->
  `type.builtin`, `return` -> `keyword.return`, `Greeter` -> `type`, `std::` ->
  `module`). `ts_highlight = true` and the highlighter is in
  `vim.treesitter.highlighter.active` in both cases, which is why "no error"
  was not evidence of working highlighting. Lua is unaffected: 334 captures and
  a clean `vim.treesitter.start`.
- T2 runtime (header switch): `~/Projects/cpp-smoke` now ships
  `compile_commands.json`. Direct `textDocument/switchSourceHeader` requests
  from a single open buffer: `src/greeter.cpp` -> `include/greeter.h` resolves
  with and without the index file; `include/greeter.h` -> `src/greeter.cpp`
  resolves with the index file and returns null without it. End-to-end through
  the keymap (`:normal ,ch`) with only `src/greeter.cpp` open: buffer switched to
  `include/greeter.h`; without the index file, from the header, the notification
  explains the missing index instead of failing silently.
