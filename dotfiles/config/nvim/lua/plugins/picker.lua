-- fzf-lua is the user-facing picker. It needs `fzf` and `rg` on the PATH, both
-- provided by the Nix neovim wrapper (modules/features/neovim.nix).
return {
  {
    "ibhagwan/fzf-lua",
    cmd = "FzfLua",
    keys = {
      { "<leader>ff", function() require("fzf-lua").files() end, desc = "Find files" },
      { "<leader>fg", function() require("fzf-lua").live_grep() end, desc = "Live grep" },
      { "<leader>fw", function() require("fzf-lua").grep_cword() end, desc = "Grep word under cursor" },
      { "<leader>fb", function() require("fzf-lua").buffers() end, desc = "Buffers" },
      { "<leader>fr", function() require("fzf-lua").oldfiles() end, desc = "Recent files" },
      { "<leader>fh", function() require("fzf-lua").help_tags() end, desc = "Help tags" },
      { "<leader>fc", function() require("fzf-lua").commands() end, desc = "Commands" },
      { "<leader>fk", function() require("fzf-lua").keymaps() end, desc = "Keymaps" },
      { "<leader>fd", function() require("fzf-lua").diagnostics_document() end, desc = "Document diagnostics" },
      { "<leader>fD", function() require("fzf-lua").diagnostics_workspace() end, desc = "Workspace diagnostics" },
      { "<leader>fs", function() require("fzf-lua").lsp_document_symbols() end, desc = "Document symbols" },
      { "<leader>fS", function() require("fzf-lua").lsp_live_workspace_symbols() end, desc = "Workspace symbols" },
      { "<leader>gs", function() require("fzf-lua").git_status() end, desc = "Git status" },
      { "<leader>gc", function() require("fzf-lua").git_commits() end, desc = "Git commits" },
      { "<leader>gb", function() require("fzf-lua").git_branches() end, desc = "Git branches" },
      { "<leader>/", function() require("fzf-lua").lgrep_curbuf() end, desc = "Grep in current buffer" },
      { "<leader>:", function() require("fzf-lua").command_history() end, desc = "Command history" },
      { "<leader>sr", function() require("fzf-lua").resume() end, desc = "Resume last search" },
    },
    opts = {
      defaults = { formatter = "path.filename_first" },
      winopts = { preview = { layout = "flex", flip_columns = 120 } },
    },
    config = function(_, opts)
      require("fzf-lua").setup(opts)
    end,
  },
}
