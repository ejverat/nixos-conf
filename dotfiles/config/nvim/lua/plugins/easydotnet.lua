-- .NET tooling: solution/project pickers, test runner, templates and NuGet, plus
-- its own dap registration. The C# language server is OmniSharp from the Nix
-- wrapper (lua/plugins/lsp.lua), so easy-dotnet's Roslyn LSP stays disabled:
-- one server per buffer, and no runtime download of a second one.
return {
  {
    "GustavEikaas/easy-dotnet.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = {
      -- "fzf" maps to fzf-lua, the picker this config already uses. That is what
      -- lets telescope.nvim leave the spec graph.
      picker = "fzf",
      lsp = { enabled = false },
    },
  },
}
