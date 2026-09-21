-- Core keymaps. Plugin-specific maps live in their own spec files.
--
-- This set is a curated port of the LazyVim defaults the config used to
-- inherit; extend it freely, the comments group them by intent.
local map = vim.keymap.set

-- Search
map("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })
map({ "n", "x", "o" }, "n", "nzzzv", { desc = "Next search result (centered)" })
map({ "n", "x", "o" }, "N", "Nzzzv", { desc = "Previous search result (centered)" })
map("x", "p", '"_dP', { desc = "Paste without yanking the replaced text" })

-- Windows
map("n", "<C-h>", "<C-w><C-h>", { desc = "Move focus to the left window" })
map("n", "<C-j>", "<C-w><C-j>", { desc = "Move focus to the lower window" })
map("n", "<C-k>", "<C-w><C-k>", { desc = "Move focus to the upper window" })
map("n", "<C-l>", "<C-w><C-l>", { desc = "Move focus to the right window" })
map("n", "<leader>-", "<C-w>s", { desc = "Split window below" })
map("n", "<leader>|", "<C-w>v", { desc = "Split window right" })
map("n", "<leader>wd", "<C-w>c", { desc = "Close window" })
map("n", "<C-Up>", "<cmd>resize +2<cr>", { desc = "Increase window height" })
map("n", "<C-Down>", "<cmd>resize -2<cr>", { desc = "Decrease window height" })
map("n", "<C-Left>", "<cmd>vertical resize -2<cr>", { desc = "Decrease window width" })
map("n", "<C-Right>", "<cmd>vertical resize +2<cr>", { desc = "Increase window width" })

-- Buffers
map("n", "<S-h>", "<cmd>bprevious<cr>", { desc = "Previous buffer" })
map("n", "<S-l>", "<cmd>bnext<cr>", { desc = "Next buffer" })
map("n", "<leader>bb", "<cmd>e #<cr>", { desc = "Switch to other buffer" })
map("n", "<leader>bd", "<cmd>bdelete<cr>", { desc = "Delete buffer" })
map("n", "<leader>bo", function()
  local current = vim.api.nvim_get_current_buf()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if buf ~= current and vim.bo[buf].buflisted then
      vim.cmd("bdelete " .. buf)
    end
  end
end, { desc = "Delete other buffers" })

-- Files, config and session
map("n", "<leader>fn", "<cmd>enew<cr>", { desc = "New file" })
map("n", "<leader>qq", "<cmd>qa<cr>", { desc = "Quit all" })
map("n", "<leader>l", "<cmd>Lazy<cr>", { desc = "Lazy" })
map("n", "<leader>ur", function()
  vim.cmd("nohlsearch")
  vim.cmd("diffupdate")
  vim.cmd("mode")
end, { desc = "Redraw and clear search highlight" })
map("n", "<leader>us", function()
  vim.wo.spell = not vim.wo.spell
  vim.notify("spell " .. (vim.wo.spell and "on" or "off"))
end, { desc = "Toggle spelling" })
map("n", "<leader>uw", function()
  vim.wo.wrap = not vim.wo.wrap
  vim.notify("wrap " .. (vim.wo.wrap and "on" or "off"))
end, { desc = "Toggle word wrap" })
map("n", "<leader>ul", function()
  vim.o.relativenumber = not vim.o.relativenumber
  vim.notify("relativenumber " .. (vim.o.relativenumber and "on" or "off"))
end, { desc = "Toggle relative line numbers" })

-- Moving lines
map("n", "<A-j>", "<cmd>execute 'move .+' . v:count1<cr>==", { desc = "Move line down" })
map("n", "<A-k>", "<cmd>execute 'move .-' . (v:count1 + 1)<cr>==", { desc = "Move line up" })
map("v", "<A-j>", ":m '>+1<cr>gv=gv", { desc = "Move selection down" })
map("v", "<A-k>", ":m '<-2<cr>gv=gv", { desc = "Move selection up" })

-- Scrolling
map("n", "<C-d>", "<C-d>zz", { desc = "Scroll down (centered)" })
map("n", "<C-u>", "<C-u>zz", { desc = "Scroll up (centered)" })

-- Formatting (conform.nvim is configured in lua/plugins/formatting.lua)
map("n", "<leader>cf", function()
  require("conform").format({ async = true, lsp_format = "fallback" })
end, { desc = "Format buffer" })
map({ "n", "v" }, "<leader>uf", function()
  vim.g.autoformat = not vim.g.autoformat
  vim.notify("autoformat " .. (vim.g.autoformat and "on" or "off"))
end, { desc = "Toggle format on save" })
map("n", "<leader>uh", function()
  local enabled = not vim.lsp.inlay_hint.is_enabled({ bufnr = 0 })
  vim.lsp.inlay_hint.enable(enabled, { bufnr = 0 })
  vim.notify("inlay hints " .. (enabled and "on" or "off"))
end, { desc = "Toggle inlay hints" })
map("n", "<leader>ud", function()
  local enabled = vim.diagnostic.is_enabled({ bufnr = 0 })
  vim.diagnostic.enable(not enabled, { bufnr = 0 })
  vim.notify("diagnostics " .. (not enabled and "on" or "off"))
end, { desc = "Toggle diagnostics" })

-- Terminal (toggleterm) and terminal-mode escape
map({ "n", "t" }, "<C-/>", function()
  require("toggleterm").toggle()
end, { desc = "Toggle terminal" })
map("n", "<leader>ft", function()
  require("toggleterm").toggle()
end, { desc = "Toggle terminal" })
map("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })
