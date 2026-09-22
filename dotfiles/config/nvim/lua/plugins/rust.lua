return {
  {
    "mrcjkb/rustaceanvim",
    version = "^7",
    -- Deferred to Rust buffers; `init` still runs at startup, which is where
    -- vim.g.rustaceanvim has to be set before the plugin loads.
    ft = "rust",
    cmd = { "RustLsp" },
    init = function()
      -- codelldb comes from the Nix wrapper (modules/features/neovim.nix). The
      -- adapter on PATH is a symlink into the VS Code lldb extension, which is
      -- also where liblldb lives, so resolve it once and derive the sibling.
      local adapter = vim.fn.exepath("codelldb")
      local liblldb = adapter ~= ""
          and (vim.fn.fnamemodify(vim.fn.resolve(adapter), ":h:h") .. "/lldb/lib/liblldb.so")
        or nil

      if adapter ~= "" and liblldb and vim.uv.fs_stat(liblldb) then
        -- Inlined from rustaceanvim.config.get_codelldb_adapter: requiring that
        -- module here would load the plugin at startup (it does now that
        -- codelldb is on the wrapper PATH), which defeats ft = "rust".
        vim.g.rustaceanvim = {
          dap = {
            adapter = {
              type = "server",
              port = "${port}",
              host = "127.0.0.1",
              executable = {
                command = adapter,
                args = { "--liblldb", liblldb, "--port", "${port}" },
              },
            },
          },
        }
      end
    end,
  },
}
