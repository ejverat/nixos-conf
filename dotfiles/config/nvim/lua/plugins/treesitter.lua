-- Tree-sitter on the `main` branch: the grammars themselves come from the Nix
-- wrapper (specs.treesitter-grammars), so nothing is installed from here and
-- highlighting/indent/folds are started with the native API.
return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    version = false,
    lazy = false,
    -- Deliberately no `build = ":TSUpdate"`. That hook rebuilds every parser
    -- nvim-treesitter knows from its own pinned stock sources into
    -- stdpath("data")/site/parser -- the same directory tree-sitter-manager.nvim
    -- installs the Unreal-patched cpp grammar into, which is the whole reason
    -- `site` is prepended below. Two owners, one directory: the 2026-09-22
    -- update replaced the patched cpp with the stock grammar and the merged cpp
    -- highlights query (USX.nvim's `unreal_body_macro` patterns) stopped
    -- building, which silently left cpp/c without any highlighting. The Nix
    -- wrapper already ships every stock grammar through the pack dir, so the
    -- hook was redundant too. Update parsers with tree-sitter-manager's own
    -- `:TSUpdateSync`, which installs cpp from taku25/tree-sitter-cpp.
    config = function()
      -- Two runtimepath details decide how cpp is highlighted:
      --
      -- 1. Parsers: tree-sitter-manager.nvim installs the Unreal-patched cpp
      --    grammar (taku25/tree-sitter-cpp) plus the custom ushader/verse
      --    grammars into stdpath("data")/site/parser, and pulls stock `c` in as
      --    cpp's dependency. Only that fork has the extra node types USX.nvim's
      --    after/queries/cpp uses (unreal_body_macro, uclass_macro,
      --    unreal_api_specifier, ...), and nvim-treesitter's own parser dir and
      --    the Nix wrapper pack both resolve a stock cpp, so site must be
      --    prepended or the cpp highlights query cannot be built at all.
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
