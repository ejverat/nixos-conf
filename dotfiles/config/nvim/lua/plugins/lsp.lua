-- Native LSP (Neovim 0.12). nvim-lspconfig only ships the per-server
-- definitions under lsp/ that vim.lsp.config discovers on the runtimepath, so
-- there is no require("lspconfig") and no legacy *.setup() call any more.
--
-- IMPORTANT: this file is the ONLY owner of the `neovim/nvim-lspconfig` spec.
-- lazy.nvim merges duplicate plugin specs and the last `config` wins, so a
-- second spec with a `config` (or `opts`) function would replace this one and
-- silently leave every server disabled. Server-specific workarounds belong
-- inside this config function.
--
-- The servers themselves come from the Nix wrapper PATH
-- (modules/features/neovim.nix), not from mason.
return {
  {
    "neovim/nvim-lspconfig",
    lazy = false,
    config = function()
      vim.diagnostic.config({
        underline = true,
        update_in_insert = false,
        severity_sort = true,
        virtual_text = { spacing = 4, source = "if_many", prefix = "●" },
        signs = {
          text = {
            [vim.diagnostic.severity.ERROR] = "",
            [vim.diagnostic.severity.WARN] = "",
            [vim.diagnostic.severity.HINT] = "",
            [vim.diagnostic.severity.INFO] = "",
          },
        },
        float = { border = "rounded", source = true },
      })

      vim.lsp.config("*", {
        capabilities = {
          workspace = {
            fileOperations = { didRename = true, willRename = true },
          },
        },
      })

      -- clangd: the argument list this config has always used (clang-tools 21
      -- is prefixed on the wrapper PATH so it shadows the FHS clangd 19).
      vim.lsp.config("clangd", {
        cmd = {
          "clangd",
          "--background-index",
          "--clang-tidy",
          "--header-insertion=iwyu",
          "--completion-style=detailed",
          "--function-arg-placeholders",
          "--fallback-style=llvm",
        },
        init_options = {
          usePlaceholders = true,
          completeUnimported = true,
          clangdFileStatus = true,
        },
      })

      -- Omnisharp reports semantic token modifiers and types with spaces in
      -- them, which Neovim cannot map (folded in from the former
      -- lua/plugins/omnisharp.lua; the client itself is launched by
      -- csharp.nvim, see lua/plugins/csharp.lua).
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

      vim.lsp.config("nixd", {})
      vim.lsp.config("ts_ls", {})
      vim.lsp.config("tailwindcss", {})
      vim.lsp.config("texlab", {})

      vim.lsp.enable({ "clangd", "nixd", "ts_ls", "tailwindcss", "texlab" })
    end,
  },
}
