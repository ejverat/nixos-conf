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
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- import/override with your plugins
    { import = "plugins" },
  },
  editor = { telescope = true },
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    -- If you know what you're doing, you can set this to `true` to have all your custom plugins lazy-loaded by default.
    lazy = false,
    -- It's recommended to leave version=false for now, since a lot the plugin that support versioning,
    -- have outdated releases, which may break your Neovim install.
    version = false, -- always use the latest git commit
    -- version = "*", -- try installing the latest stable version for plugins that support semver
  },
  install = { colorscheme = { "tokyonight", "habamax" } },
  -- Allow long build steps (e.g. the UNL.nvim Rust scanner takes ~5 min to compile).
  git = { timeout = 600 },
  checker = {
    enabled = true, -- check for plugin updates periodically
    notify = false, -- notify on update
  }, -- automatically check for plugin updates
  performance = {
    -- Keep the Nix-provided packpath so the tree-sitter grammars installed via
    -- the neovim wrapper (COLLATED_TS_GRAMMARS) stay available. lazy.nvim resets
    -- packpath to $VIMRUNTIME by default, which breaks those parsers.
    reset_packpath = false,
    rtp = {
      -- Keep the wrapper-provided runtimepath. The nix wrapper (wrapper-modules)
      -- loads this config from $HOME/.dotfiles/config/nvim by prepending it to
      -- the rtp, while stdpath("config") stays $HOME/.config/nvim. lazy.nvim's
      -- default rtp.reset = true rebuilds the rtp from stdpath("config"), which
      -- drops the config dir, so `import = "plugins"` resolves nothing and
      -- lazy reports 'No specs found for module "plugins"'.
      reset = false,
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        -- "matchit",
        -- "matchparen",
        -- "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
