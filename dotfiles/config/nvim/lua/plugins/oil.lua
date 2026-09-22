return {
  "stevearc/oil.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  -- Deferred: `-` opens the parent directory and `:Oil` exists on demand, so
  -- neither the plugin nor its devicons dependency belong in the startup set.
  cmd = "Oil",
  keys = {
    { "-", "<CMD>Oil<CR>", desc = "Open parent directory" },
  },
  opts = {
    columns = { "icon" },
    keymaps = {
      ["<C-h>"] = false,
      ["<C-l>"] = false,
      ["<C-k>"] = false,
      ["<C-j>"] = false,
      ["<M-h>"] = "actions.select_split",
    },
    view_options = { show_hidden = true },
  },
}
