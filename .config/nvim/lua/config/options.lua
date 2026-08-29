vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

local opt = vim.opt

opt.number = true
opt.relativenumber = false -- absolute by default; <leader>N toggles relative
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

opt.inccommand = "split" -- preview :s/ matches live, and list every changed line
opt.confirm = true -- prompt to save on :q of a dirty buffer, rather than erroring

opt.termguicolors = true
opt.mouse = "a"

opt.swapfile = false

opt.autoread = true

opt.clipboard = "unnamedplus"

opt.updatetime = 250
opt.timeoutlen = 500
opt.showmode = false
opt.cmdheight = 0

-- Persist undo history to disk so it survives closing a file (and powers the
-- undotree plugin across sessions). Undo files live under stdpath("state")/undo.
opt.undofile = true

-- Diagnostics stay as a gutter sign only; land on the line and <leader>d opens
-- the float with the message. Inline virtual_text (even errors-only) was more
-- noise than it was worth. severity_sort so the sign/float belong to the worst
-- diagnostic on the line, not whichever server reported first.
vim.diagnostic.config({
  virtual_text = false,
  severity_sort = true,
})

-- Fixed RPC socket for external tooling (an MCP server that reads buffers /
-- diagnostics / review state), stable across restarts — unlike the per-instance
-- $NVIM path, which tmux keeps stale after an nvim restart.
--
-- Only the "main" nvim may claim it: a nested instance (spawned inside our own
-- terminal, e.g. `git commit` — $NVIM is set there) must not, or it would
-- delete the outer session's live socket and steal the path. And a socket file
-- on disk is only reclaimed when nothing answers on it (a leftover from a
-- crashed/killed run), not when another live nvim owns it.
if not vim.env.NVIM then
  local rpc_socket = vim.fs.joinpath(vim.env.XDG_RUNTIME_DIR or "/tmp", "nvim.sock")
  if vim.uv.fs_stat(rpc_socket) then
    local ok, chan = pcall(vim.fn.sockconnect, "pipe", rpc_socket, { rpc = true })
    if ok and chan > 0 then
      pcall(vim.fn.chanclose, chan) -- someone's alive on it: leave it theirs
    else
      os.remove(rpc_socket) -- stale leftover: reclaim
      pcall(vim.fn.serverstart, rpc_socket)
    end
  else
    pcall(vim.fn.serverstart, rpc_socket)
  end
end
