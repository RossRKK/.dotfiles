-- Runtime for the headless test suite: this config plus plenary. Deliberately
-- excludes lazy.nvim, so no plugin specs load and no plugin's config() runs --
-- specs require the modules they exercise directly and fake whatever plugin
-- objects those modules touch.

-- This checkout's config, not ~/.config/nvim, so a worktree's suite tests that worktree.
local config = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(config)
-- Specs share helpers as require("tests.helpers.<name>").
package.path = config .. "/?.lua;" .. package.path

local plugins = require("tests.helpers.plugins")
if vim.fn.isdirectory(plugins.dir("plenary.nvim")) == 0 then
  error("plenary.nvim not found at " .. plugins.dir("plenary.nvim") .. " -- open nvim once to let lazy install it")
end
-- fishmonger's modules too, so specs use its real glyph widths; requiring a module runs no setup().
plugins.add("plenary.nvim", "fishmonger.nvim")
vim.opt.swapfile = false
