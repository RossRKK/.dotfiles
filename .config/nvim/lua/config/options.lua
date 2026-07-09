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

-- Fixed RPC socket for external tooling (an MCP server that reads buffers /
-- diagnostics / review state), stable across restarts — unlike the per-instance
-- $NVIM path, which tmux keeps stale after an nvim restart. We run one nvim, so
-- reclaim a socket left by a previous run before binding.
local rpc_socket = vim.fs.joinpath(vim.env.XDG_RUNTIME_DIR or "/tmp", "nvim.sock")
if vim.uv.fs_stat(rpc_socket) then
  os.remove(rpc_socket)
end
pcall(vim.fn.serverstart, rpc_socket)
