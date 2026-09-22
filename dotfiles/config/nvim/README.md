# Neovim configuration

Own plugin specification for Neovim 0.12: no distribution layer. LazyVim was
removed in favour of ~25 specs in `lua/plugins/`, one engine per function and
lazy loading by `event`/`ft`/`cmd`/`keys` (six plugins load at startup).

## Layout

| Path | What it is |
| --- | --- |
| `init.lua` | entry point: `config.options` -> `config.lazy` -> `config.autocmds` -> `config.keymaps` |
| `lua/config/` | options, keymaps, autocmds (including the LSP attach keymaps), lazy.nvim bootstrap |
| `lua/plugins/` | the plugin specification, one file per concern |
| `lazy-lock.json` | pinned plugin revisions, the tracked snapshot (see below) |

This directory is materialized **read-only** from the Nix store at
`~/.dotfiles/config/nvim` by `modules/features/dotfiles.nix`, and the wrapper in
`modules/features/neovim.nix` points Neovim at it (`config_directory`) while
`stdpath("config")` stays `~/.config/nvim`. Consequences:

- editing anything here needs a commit and `sudo nixos-rebuild switch --flake .#chopper`;
- everything Neovim writes (lazy.nvim state, the lockfile, the plugin store) lives
  in `~/.config/nvim` and `~/.local/share/nvim`, outside this repository;
- lazy.nvim runs with `performance.rtp.reset = false` and
  `performance.reset_packpath = false`, which is what keeps the wrapper's
  runtimepath and its tree-sitter grammars alive.

Language servers, debug adapters, formatters and the tree-sitter grammars come
from the Nix wrapper (`modules/features/neovim.nix`, `neovimExtraPkgs`), not from
mason. Plugins come from lazy.nvim.

## Lockfile policy

`lazy-lock.json` exists in two places and they are not the same file:

- `~/.config/nvim/lazy-lock.json` — what lazy.nvim writes after install/update;
- `dotfiles/config/nvim/lazy-lock.json` — this tracked snapshot.

`scripts/nvim-lock.sh` bridges them:

```sh
./scripts/nvim-lock.sh check    # report drift (sorted, order-independent)
./scripts/nvim-lock.sh sync     # runtime -> repo, after `:Lazy update`
./scripts/nvim-lock.sh seed     # repo -> runtime, on a fresh machine
```

After `:Lazy update`, run `sync` so the repository pins what actually runs. On a
new machine, run `seed` first and then `:Lazy restore` in Neovim to install the
exact revisions instead of the latest ones.

## Fixtures

Manual smoke tests live outside this repository: `~/Projects/cpp-smoke` (clangd,
tree-sitter, textobjects, codelldb) and `~/Projects/csharp-smoke` (a minimal
`.csproj` for OmniSharp).
