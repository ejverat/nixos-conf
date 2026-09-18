return {
  {
    "mrcjkb/rustaceanvim",
    version = "^7",
    lazy = false,
    init = function()
      local mason_root = vim.fn.stdpath("data") .. "/mason"
      local extension_path = mason_root .. "/packages/codelldb/extension/"
      local codelldb_path = extension_path .. "adapter/codelldb"
      local liblldb_path = extension_path .. "lldb/lib/liblldb.so"
      local cfg = require("rustaceanvim.config")

      vim.g.rustaceanvim = {
        dap = {
          adapter = cfg.get_codelldb_adapter(codelldb_path, liblldb_path),
        },
      }
    end,
  },
}
