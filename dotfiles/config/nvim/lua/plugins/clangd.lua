-- C/C++ extras on top of the native clangd config in lua/plugins/lsp.lua:
-- clangd_extensions (AST, type hierarchy, symbol info, source/header switch)
-- and the codelldb adapter for nvim-dap.
--
-- Note: this version of clangd_extensions has no inlay-hint feature, so the
-- hints come from the native `vim.lsp.inlay_hint` enabled on LspAttach.
return {
  {
    "p00f/clangd_extensions.nvim",
    ft = { "c", "cpp", "objc", "objcpp" },
    keys = {
      {
        "<leader>ch",
        function()
          if #vim.lsp.get_clients({ bufnr = 0, name = "clangd" }) == 0 then
            vim.notify("clangd is not attached to this buffer yet", vim.log.levels.WARN)
            return
          end
          -- Same request as :ClangdSwitchSourceHeader, with the two failure
          -- modes spelled out: clangd answers null when it cannot work out the
          -- counterpart, which for header -> source means the project has no
          -- index yet (a compile_commands.json enables --background-index).
          vim.lsp.buf_request(0, "textDocument/switchSourceHeader", {
            uri = vim.uri_from_bufnr(0),
          }, function(err, result)
            if err then
              vim.notify("switch source/header: " .. (err.message or "request failed"), vim.log.levels.ERROR)
            elseif not result then
              vim.notify(
                "clangd could not determine the corresponding file; header -> source needs an index (add compile_commands.json to the project)",
                vim.log.levels.WARN
              )
            else
              vim.cmd.edit(vim.fn.fnameescape(vim.uri_to_fname(result)))
            end
          end)
        end,
        desc = "Switch source/header",
      },
      { "<leader>cA", "<cmd>ClangdAST<cr>", desc = "Show AST" },
    },
    opts = {
      ast = {
        role_icons = {
          type = "",
          declaration = "",
          expression = "",
          specifier = "",
          statement = "",
          ["template argument"] = "",
        },
        kind_icons = {
          Compound = "",
          Recovery = "",
          TranslationUnit = "",
          PackExpansion = "",
          TemplateTypeParm = "",
          TemplateTemplateParm = "",
          TemplateParamObject = "",
        },
      },
    },
    config = function(_, opts)
      require("clangd_extensions").setup(opts)
    end,
  },
  {
    "mfussenegger/nvim-dap",
    optional = true,
    opts = function()
      local dap = require("dap")
      if not dap.adapters.codelldb then
        -- codelldb comes from the Nix wrapper (see modules/features/neovim.nix).
        dap.adapters.codelldb = {
          type = "server",
          host = "localhost",
          port = "${port}",
          executable = {
            command = vim.fn.exepath("codelldb") ~= "" and vim.fn.exepath("codelldb") or "codelldb",
            args = { "--port", "${port}" },
          },
        }
      end
      for _, lang in ipairs({ "c", "cpp" }) do
        dap.configurations[lang] = {
          {
            type = "codelldb",
            request = "launch",
            name = "Launch file",
            program = function()
              return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
            end,
            cwd = "${workspaceFolder}",
          },
          {
            type = "codelldb",
            request = "attach",
            name = "Attach to process",
            processId = require("dap.utils").pick_process,
            cwd = "${workspaceFolder}",
          },
        }
      end
    end,
  },
}
