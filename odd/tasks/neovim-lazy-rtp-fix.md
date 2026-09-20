# Feature: fix lazy.nvim plugin spec resolution under the Neovim nix wrapper

## Goal

`nvim` starts with the full LazyVim + custom layer: no
`notify.error lazy.nvim No specs found for module "plugins"` notification, and
every module in `dotfiles/config/nvim/lua/plugins/*.lua` (28 files) resolves and
loads.

## Root cause (validated 2026-09-19)

The flake wrapper in `modules/features/neovim.nix` sets
`settings.config_directory = "$HOME/.dotfiles/config/nvim"`. `wrapper-modules`
implements that by prepending the directory to the `runtimepath`, removing
`stdpath("config")` from rtp/packpath, and sourcing `init.lua` through
`VIMINIT` (`lua require("nix-info.init_main")`). It does **not** change
`vim.fn.stdpath("config")`, which stays `$HOME/.config/nvim`.

lazy.nvim's default `performance.rtp.reset = true`
(`lazy/core/config.lua:198`) replaces the whole runtimepath with a list built
from `stdpath("config")`:

```lua
vim.opt.rtp = {
  vim.fn.stdpath("config"), vim.fn.stdpath("data") .. "/site", M.me,
  vim.env.VIMRUNTIME, lib, vim.fn.stdpath("config") .. "/after",
}
```

`$HOME/.dotfiles/config/nvim` is dropped there. `import = "plugins"` is resolved
through the runtimepath (`Util.find_root` -> `nvim_get_runtime_file`), so
`imported == 0` and `lazy/core/plugin.lua:209-210` raises
`No specs found for module "plugins"`.

Evidence (traced through `package.searchers` in the real wrapper):

```
== probe start  stdpath_config=/home/ejverat/.config/nvim
== rtp_has_dotfiles_at_probe_start=true
REQ config.lazy -> /home/ejverat/.dotfiles/config/nvim/lua/config/lazy.lua
REQ lazy -> ~/.local/share/nvim/lazy/lazy.nvim/lua/lazy/init.lua
MISS lazyvim.config ... [rtp_has_dotfiles=false]   <- dropped inside setup
```

Controlled experiment on a temporary copy of the config:

| case | `performance.rtp.reset` | `Util.lsmod("plugins")` |
| --- | --- | --- |
| control | `true` (default) | 0 -> error |
| fix | `false` | 28 -> resolves |

Wiring introduced by `8805dde` (2026-06-14), so the notification predates the
2026-09-19 reboot; only the extra plugins were silently missing.

## Decision

Keep the wrapper design (config materialized read-only at
`~/.dotfiles/config/nvim`, lazy state writable at `~/.config/nvim`) and disable
lazy.nvim's runtimepath reset. Rejected alternative: moving the config to
`~/.config/nvim` (structural change across the wrapper, the dotfiles home module
and the gear5th portable layer) -- revisit only if the double config path becomes
a real maintenance burden.

## Tasks

- [x] T1 Add `performance.rtp.reset = false` (with rationale comment) to
      `dotfiles/config/nvim/lua/config/lazy.lua`. Done 2026-09-19: single `rtp`
      key, `nvim --headless --clean -c 'loadfile(...)'` reports LUA SYNTAX OK,
      diff = +7 lines. Not yet effective at runtime (config is materialized from
      the store until the next switch).
- [x] T2 Rebuild chopper (`sudo nixos-rebuild switch --flake .#chopper`) and
      verify a clean `nvim` start. Done 2026-09-19 by the user; the config was
      re-materialized (`~/.dotfiles/.../lazy.lua` -> store path
      `zqix7hqk71xcg40k4bshvrbak7qw313l-hm_nvim` with `reset = false`). Runtime
      evidence: `rtp_has_dotfiles=true` after `require("lazy").setup`,
      `Util.lsmod("plugins")` = 28, `rtp_reset_option=false`, zero notifications
      on a second start, `:messages` free of `No specs found`, startup 1 s.
- [x] T3 Restore the missing plugins and confirm the lockfile. Done: the first
      post-fix start installed the missing 43 plugins (`installed_plugin_dirs`
      = 75, all of `molten|oil.nvim|toggleterm|neogen|cmake-tools` present) and
      `~/.config/nvim/lazy-lock.json` reached 75 entries, stable across runs.
- [ ] T4 Record the decision in memory and close the feature.
- [x] T5 Commit the work unit (repo edit + feature doc) once T2 verifies.
      Ordering decided by the user 2026-09-19: commit only after runtime
      verification; the agent does not commit unprompted.
      Delivered: issue #21 (`type:bug` + `status:approved`), commit `2a8ab3d`
      pushed to `origin/fix/nvim-lazy-rtp-path`, PR #22 open against `main`
      (MERGEABLE, label `type:bug`, body links `Closes #21`; the repo has no CI
      workflows, so no checks run). Merge remains the user's decision.

## Lockfile reconciliation (76 in git vs 75 at runtime)

- `telescope-fzf-native.nvim`: inert by design. `lua/plugins/example.lua` starts
  with `if true then return {} end`, so the starter snippet (and its
  `build = "make"` dependency) is never imported. Uncommenting it also needs
  `make`/`cc` on the wrapper PATH, which the nvim process does not have today.
- `nvim-platformio.lua` + `telescope-ui-select.nvim`: disabled on purpose by the
  `cond` in `lua/plugins/platformio.lua` (no `platformio.ini` in cwd, plugin
  already installed). They stay installed and locked, and re-enable with
  `:Pioinit` or a PlatformIO project.

No unexplained difference remains for the 73 resolved plugin specs.

## Verification evidence

- T1: file read-back; duplicate `rtp` key avoided (single table).
- T2: `nvim --headless -c 'lua ...'` probe shows
  `rtp_has_dotfiles=true` after `require("lazy").setup`.
- T3: `~/.config/nvim/lazy-lock.json` entry count and `:Lazy` health.
