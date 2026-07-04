vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

local opt = vim.opt

opt.number = true
opt.relativenumber = true
opt.signcolumn = "yes"
opt.cursorline = true

opt.tabstop = 4
opt.shiftwidth = 4
opt.expandtab = true
opt.smartindent = true

opt.wrap = true
opt.linebreak = true -- break wrapped lines at word boundaries, not mid-word
opt.breakindent = true -- wrapped continuation lines keep the line's indent
opt.showbreak = "↪ " -- marker at the start of each wrapped continuation line
opt.breakindentopt = "sbr" -- draw showbreak after the indent (dimmed via NonText)
opt.scrolloff = 8

opt.splitright = true
opt.splitbelow = true

opt.ignorecase = true
opt.smartcase = true

opt.termguicolors = true
opt.mouse = "a"

opt.undofile = true
opt.swapfile = false

opt.autoread = true

opt.clipboard = "unnamedplus"

opt.updatetime = 250
opt.timeoutlen = 300
opt.showmode = false
opt.cmdheight = 0

