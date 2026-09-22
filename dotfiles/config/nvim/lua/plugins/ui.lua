-- UI surface: colorscheme, statusline, git signs, key hints, mini modules.
-- The decorative LazyVim layer (snacks, noice, trouble, bufferline, ...) is
-- intentionally not replaced; see odd/tasks/neovim-minimal-refactor.md.
return {
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = { style = "night" },
    config = function(_, opts)
      require("tokyonight").setup(opts)
      pcall(vim.cmd.colorscheme, "tokyonight")
    end,
  },
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    opts = { options = { globalstatus = true, theme = "auto" } },
  },
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      signs = {
        add = { text = "▎" },
        change = { text = "▎" },
        delete = { text = "" },
        topdelete = { text = "" },
        changedelete = { text = "▎" },
      },
      on_attach = function(buf)
        local gs = require("gitsigns")
        local function map(lhs, rhs, desc)
          vim.keymap.set("n", lhs, rhs, { buffer = buf, desc = desc })
        end
        map("]h", function() gs.nav_hunk("next") end, "Next hunk")
        map("[h", function() gs.nav_hunk("prev") end, "Previous hunk")
        map("<leader>ghs", gs.stage_hunk, "Stage hunk")
        map("<leader>ghr", gs.reset_hunk, "Reset hunk")
        map("<leader>ghp", gs.preview_hunk, "Preview hunk")
        map("<leader>ghb", function() gs.blame_line({ full = true }) end, "Blame line")
        map("<leader>ghd", gs.diffthis, "Diff this")
      end,
    },
  },
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      spec = {
        { "<leader>b", group = "buffer" },
        { "<leader>c", group = "code" },
        { "<leader>f", group = "find" },
        { "<leader>g", group = "git" },
        { "<leader>gh", group = "git hunk" },
        { "<leader>m", group = "molten" },
        { "<leader>r", group = "refactor" },
        { "<leader>u", group = "ui" },
        { "<leader>w", group = "window" },
      },
    },
  },
  -- Upstream moved to the nvim-mini org; the older echasnovski URLs redirect
  -- to the same commits but lazy.nvim flags the origin mismatch, so use the
  -- canonical ones.
  { "nvim-mini/mini.ai", version = false, event = "VeryLazy", opts = {} },
  { "nvim-mini/mini.pairs", version = false, event = "InsertEnter", opts = {} },
  { "nvim-mini/mini.icons", version = false, lazy = false, opts = {} },
}
