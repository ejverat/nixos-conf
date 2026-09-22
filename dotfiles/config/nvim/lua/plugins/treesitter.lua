-- Tree-sitter on the `main` branch: the grammars themselves come from the Nix
-- wrapper (specs.treesitter-grammars), so nothing is installed from here and
-- highlighting/indent/folds are started with the native API.
return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    version = false,
    lazy = false,
    build = ":TSUpdate",
    config = function()
      -- Two runtimepath details decide how cpp is highlighted:
      --
      -- 1. Parsers: the Unreal suite installs patched grammars (cpp, c, ushader,
      --    verse) into stdpath("data")/site/parser, and USX.nvim ships
      --    after/queries/cpp queries using their extra node types
      --    (unreal_body_macro). The Nix wrapper's stock grammars are earlier on
      --    the runtimepath, so site must be prepended or the cpp highlights
      --    query cannot be built at all.
      -- 2. Queries: the Unreal stack also drops its fork of the cpp/c queries
      --    into stdpath("data")/site/queries, and that fork has no
      --    `; inherits: c` line -- which is exactly where cpp keywords, types
      --    and preprocessor captures come from. nvim-treesitter keeps the
      --    upstream set under <plugin>/runtime/queries, so exposing that
      --    directory restores them while the Unreal patterns stay in the merge.
      local site = vim.fn.stdpath("data") .. "/site"
      if vim.uv.fs_stat(site .. "/parser") then
        vim.opt.rtp:prepend(site)
      end
      local ts = require("lazy.core.config").plugins["nvim-treesitter"]
      if ts and vim.uv.fs_stat(ts.dir .. "/runtime/queries") then
        vim.opt.rtp:prepend(ts.dir .. "/runtime")
      end

      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("config_treesitter", { clear = true }),
        callback = function(ev)
          -- pcall handles filetypes without an installed grammar
          if not pcall(vim.treesitter.start, ev.buf) then
            return
          end
          local ok, TS = pcall(require, "nvim-treesitter")
          if ok and TS.indentexpr then
            vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
          -- Folds stay available (zc/za/zM) but start open: with the default
          -- foldlevel = 0 every fold is closed as soon as it appears, and a
          -- cursor jump into a closed fold is a no-op (foldopen does not
          -- include jumps). That silently broke snippet placeholder jumps on
          -- any multi-line snippet, and would do the same for other jumps into
          -- folded regions.
          vim.wo.foldmethod = "expr"
          vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
          vim.wo.foldlevel = 99
        end,
      })
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    branch = "main",
    version = false,
    event = "VeryLazy",
    config = function()
      require("nvim-treesitter-textobjects").setup({ move = { enable = true, set_jumps = true } })

      local moves = {
        goto_next_start = { ["]f"] = "@function.outer", ["]c"] = "@class.outer", ["]a"] = "@parameter.inner" },
        goto_next_end = { ["]F"] = "@function.outer", ["]C"] = "@class.outer", ["]A"] = "@parameter.inner" },
        goto_previous_start = { ["[f"] = "@function.outer", ["[c"] = "@class.outer", ["[a"] = "@parameter.inner" },
        goto_previous_end = { ["[F"] = "@function.outer", ["[C"] = "@class.outer", ["[A"] = "@parameter.inner" },
      }

      local function attach(buf)
        for method, keymaps in pairs(moves) do
          for key, query in pairs(keymaps) do
            vim.keymap.set({ "n", "x", "o" }, key, function()
              if vim.wo.diff and key:find("[cC]") then
                return vim.cmd("normal! " .. key)
              end
              require("nvim-treesitter-textobjects.move")[method](query, "textobjects")
            end, { buffer = buf, silent = true, desc = "TS " .. method .. " " .. query })
          end
        end
      end

      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("config_textobjects", { clear = true }),
        callback = function(ev) attach(ev.buf) end,
      })
      vim.tbl_map(attach, vim.api.nvim_list_bufs())
    end,
  },
}
