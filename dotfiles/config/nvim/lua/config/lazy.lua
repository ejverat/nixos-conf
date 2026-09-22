-- Bootstrap lazy.nvim and load every spec under lua/plugins.
--
-- The Nix wrapper (modules/features/neovim.nix) prepends
-- $HOME/.dotfiles/config/nvim to the runtimepath and sources init.lua through
-- VIMINIT while stdpath("config") stays $HOME/.config/nvim. Both performance
-- switches below are required to keep that layout working:
--   * reset = false: lazy.nvim would rebuild the rtp from stdpath("config"),
--     dropping the config dir so `import = "plugins"` resolves nothing.
--   * reset_packpath = false: keeps the wrapper-provided packpath so the
--     tree-sitter grammars injected by the wrapper stay available.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    { import = "plugins" },
  },
  defaults = {
    -- Specs opt into lazy loading with event/ft/cmd/keys; see lua/plugins.
    lazy = false,
    -- A lot of plugins have outdated releases that may break Neovim, so track
    -- the latest commit (lazy-lock.json pins the exact revision).
    version = false,
  },
  install = { colorscheme = { "tokyonight", "habamax" } },
  -- Allow long build steps (e.g. the UNL.nvim Rust scanner takes ~5 min to compile).
  git = { timeout = 600 },
  checker = {
    enabled = true, -- check for plugin updates periodically
    notify = false, -- notify on update
  },
  performance = {
    reset_packpath = false,
    rtp = {
      reset = false,
      disabled_plugins = {
        "gzip",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
