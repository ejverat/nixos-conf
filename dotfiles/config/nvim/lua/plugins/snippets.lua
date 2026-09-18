return {
  {
    "rafamadriz/friendly-snippets",
    dependencies = { "L3MON4D3/LuaSnip" },
    config = function()
      require("luasnip.loaders.from_vscode").lazy_load({
        paths = {
          -- Load JS/TS/React snippets
          vim.fn.stdpath("data") .. "/lazy/friendly-snippets/snippets/javascript",
          vim.fn.stdpath("data") .. "/lazy/friendly-snippets/snippets/typescript",
        },
      })
    end,
  },
}
