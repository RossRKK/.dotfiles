-- Runtime for the headless test suite: this config plus plenary (already on disk
-- as a telescope dependency). Deliberately excludes lazy.nvim, so no plugin
-- specs load and no plugin's config() runs -- specs require the modules they
-- exercise directly and fake whatever plugin objects those modules touch.

local config = vim.fn.expand("~/.config/nvim")
local plenary = vim.fn.stdpath("data") .. "/lazy/plenary.nvim"

if vim.fn.isdirectory(plenary) == 0 then
  error("plenary.nvim not found at " .. plenary .. " -- open nvim once to let lazy install it")
end

vim.opt.runtimepath:prepend(config)
vim.opt.runtimepath:prepend(plenary)
vim.opt.swapfile = false
