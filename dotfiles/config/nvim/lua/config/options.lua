-- Editor options. Loaded before lazy.nvim starts, so plugin specs can read them.
local o = vim.o
local opt = vim.opt

vim.g.mapleader = ","
vim.g.maplocalleader = "\\"

-- Consumed by lua/plugins/formatting.lua (format on save toggle).
vim.g.autoformat = true

-- Editing
o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.softtabstop = 2
o.autoindent = true
o.smartindent = true
o.breakindent = true
o.linebreak = true
o.undofile = true
o.confirm = true
opt.jumpoptions = "view"

-- UI
o.number = true
o.relativenumber = true
o.signcolumn = "yes"
o.cursorline = true
o.termguicolors = true
o.laststatus = 3
o.showmode = false
o.winborder = "rounded"
opt.fillchars = { eob = " " }
o.list = true
opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }
o.scrolloff = 4
o.sidescrolloff = 8
o.wrap = false

-- Search and replace
o.ignorecase = true
o.smartcase = true
o.inccommand = "split"
opt.spelllang = { "en" }

-- Sessions, input and timing
opt.sessionoptions = { "buffers", "curdir", "folds", "help", "tabpages", "winsize", "terminal", "globals" }
o.updatetime = 250
o.timeoutlen = 300
o.mouse = "a"
o.clipboard = "unnamedplus"
opt.shortmess:append("c")

-- Windows
o.splitright = true
o.splitbelow = true
o.splitkeep = "screen"
