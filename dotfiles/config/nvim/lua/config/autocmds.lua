-- Autocmds: editor behaviour that does not belong to a single plugin spec.
local augroup = vim.api.nvim_create_augroup("config", { clear = true })
local function au(event, opts)
  opts.group = augroup
  return vim.api.nvim_create_autocmd(event, opts)
end

-- Highlight the yanked region
au("TextYankPost", {
  callback = function()
    vim.hl.on_yank({ higroup = "IncSearch", timeout = 150 })
  end,
})

-- Restore the last cursor position when a file is reopened
au("BufReadPost", {
  callback = function(ev)
    if vim.tbl_contains({ "gitcommit" }, vim.bo[ev.buf].filetype) then
      return
    end
    local mark = vim.api.nvim_buf_get_mark(ev.buf, '"')
    if mark[1] > 0 and mark[1] <= vim.api.nvim_buf_line_count(ev.buf) then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- Continued comments surprise more than they help
au("FileType", {
  callback = function()
    vim.opt_local.formatoptions:remove({ "c", "r", "o" })
  end,
})

-- Close transient windows with q
au("FileType", {
  pattern = { "help", "man", "qf", "checkhealth", "lazy", "lspinfo", "notify", "startuptime", "tsplayground", "query" },
  callback = function(ev)
    vim.bo[ev.buf].buflisted = false
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = ev.buf, silent = true, desc = "Close window" })
  end,
})

-- Keep splits balanced when the terminal is resized
au("VimResized", { callback = function() vim.cmd("tabdo wincmd =") end })

-- Pick up changes made to the file on disk
au({ "FocusGained", "TermClose", "TermLeave" }, {
  callback = function()
    if vim.o.buftype ~= "nofile" then
      vim.cmd("checktime")
    end
  end,
})

-- Tell WezTerm whether this pane is running Neovim, so wezterm.lua's
-- split_nav() forwards CTRL+h/j/k/l to Neovim instead of resizing panes: its
-- is_vim() checks the IS_NVIM user var, and nothing was setting it.
--
-- WezTerm has no `cli set-user-var` subcommand in this version, so this uses the
-- OSC 1337 SetUserVar escape. Inside tmux the sequence has to be wrapped in
-- tmux's passthrough (allow-passthrough, on by default since tmux 3.7) or tmux
-- swallows it. Purely additive: without WEZTERM_PANE nothing happens, so the
-- config stays portable.
local function set_wezterm_user_var(name, value)
  if not vim.env.WEZTERM_PANE then
    return
  end
  local seq = "\27]1337;SetUserVar=" .. name .. "=" .. vim.base64.encode(value) .. "\7"
  if vim.env.TMUX then
    seq = "\27Ptmux;\27" .. seq .. "\27\\"
  end
  pcall(function()
    io.stdout:write(seq)
    io.stdout:flush()
  end)
end

au("VimEnter", {
  callback = function()
    -- after the TUI is up, so the escape is not swallowed by startup
    vim.schedule(function() set_wezterm_user_var("IS_NVIM", "true") end)
  end,
})

au("VimLeavePre", {
  callback = function() set_wezterm_user_var("IS_NVIM", "false") end,
})

-- LSP: buffer-local keymaps plus inlay hints for every attached client
au("LspAttach", {
  callback = function(ev)
    local buf = ev.buf
    local function bmap(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc })
    end

    bmap("n", "gd", vim.lsp.buf.definition, "Goto definition")
    bmap("n", "gD", vim.lsp.buf.declaration, "Goto declaration")
    bmap("n", "gr", vim.lsp.buf.references, "References")
    bmap("n", "gI", vim.lsp.buf.implementation, "Goto implementation")
    bmap("n", "gy", vim.lsp.buf.type_definition, "Goto type definition")
    bmap("n", "K", vim.lsp.buf.hover, "Hover")
    bmap("i", "<C-k>", vim.lsp.buf.signature_help, "Signature help")
    bmap("n", "<leader>ca", vim.lsp.buf.code_action, "Code action")
    bmap("v", "<leader>ca", vim.lsp.buf.code_action, "Code action")
    bmap("n", "<leader>cr", vim.lsp.buf.rename, "Rename symbol")
    bmap("n", "<leader>cd", vim.diagnostic.open_float, "Line diagnostics")
    bmap("n", "]d", function() vim.diagnostic.jump({ count = 1, float = true }) end, "Next diagnostic")
    bmap("n", "[d", function() vim.diagnostic.jump({ count = -1, float = true }) end, "Previous diagnostic")

    if vim.lsp.inlay_hint then
      pcall(vim.lsp.inlay_hint.enable, true, { bufnr = buf })
    end
  end,
})
