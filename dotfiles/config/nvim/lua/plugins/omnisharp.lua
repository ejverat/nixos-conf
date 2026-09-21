-- Omnisharp workaround: the server reports semantic token modifiers/types with
-- spaces in them, which Neovim cannot map. See lua/plugins/csharp.lua for the
-- client that actually launches the server.
--
-- T3 of odd/tasks/neovim-minimal-refactor.md consolidates this file,
-- csharp.nvim and easy-dotnet.nvim into a single C#/dotnet stack.
return {
  {
    "neovim/nvim-lspconfig",
    optional = true,
    config = function()
      vim.lsp.config("omnisharp", {
        on_attach = function(client)
          if client.name ~= "omnisharp" then
            return
          end
          local provider = client.server_capabilities.semanticTokensProvider
          if not provider or not provider.legend then
            return
          end
          for _, key in ipairs({ "tokenModifiers", "tokenTypes" }) do
            local list = provider.legend[key]
            if list then
              for i, value in ipairs(list) do
                list[i] = value:gsub(" ", "_")
              end
            end
          end
        end,
      })
    end,
  },
}
