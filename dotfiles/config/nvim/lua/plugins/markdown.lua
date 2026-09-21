return {
  -- Markdown rendering inside the buffer (moved here from the old texlab.lua,
  -- which only existed to import it).
  { "OXY2DEV/markview.nvim", lazy = false },

  {
    "selimacerbas/markdown-preview.nvim",
    dependencies = {
      "selimacerbas/live-server.nvim",
    },
    cmd = { "MarkdownPreview", "MarkdownPreviewStop", "MarkdownPreviewRefresh" },
    keys = {
      {
        "<C-n>",
        function()
          local mp = require("markdown_preview")
          if mp._server_instance ~= nil then
            mp.stop()
          else
            mp.start()
          end
        end,
        desc = "Toggle Markdown Preview",
      },
    },
    config = function()
      require("markdown_preview").setup({})
    end,
  },
}
