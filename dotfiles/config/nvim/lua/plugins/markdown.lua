return {
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
}
