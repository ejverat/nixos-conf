return {
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    -- Deferred: the <C-/> and <leader>ft mappings in lua/config/keymaps.lua
    -- require("toggleterm") on demand, which lazy.nvim resolves to this spec.
    cmd = { "ToggleTerm", "TermExec", "ToggleTermToggleAll" },
    config = function()
      require("toggleterm").setup()
    end,
  },
}
