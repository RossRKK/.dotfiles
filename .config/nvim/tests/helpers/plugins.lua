-- Puts the plugins a spec runs for real on the runtimepath, from where the nvim
-- under test loads them: the nix build (or a NVIM_DEV_PLUGINS checkout, as
-- config/lazy.lua resolves it), else lazy.nvim's own install.
local M = {}

local nix_build = require("util.nix_build").info

---@type fun(plugin: { name: string }): string
local dir_of
local plugin_dirs = require("config.plugin_dirs")
if nix_build then
  dir_of = plugin_dirs.for_build(nix_build, vim.env.NVIM_DEV_PLUGINS)
else
  local dev = plugin_dirs.parse_dev(vim.env.NVIM_DEV_PLUGINS, vim.fn.expand("~/dev"))
  -- lazy.nvim's dev = true plugins load from ~/dev when checked out there.
  local forks = { ["agentic.nvim"] = true, ["fishmonger.nvim"] = true, ["nitpick.nvim"] = true, ["triage.nvim"] = true }
  dir_of = function(plugin)
    local checkout = vim.fn.expand("~/dev/") .. plugin.name
    if dev[plugin.name] then
      return dev[plugin.name]
    elseif forks[plugin.name] and vim.fn.isdirectory(checkout) == 1 then
      return checkout
    end
    return vim.fn.stdpath("data") .. "/lazy/" .. plugin.name
  end
end

---@param name string the plugin as lazy.nvim names it, e.g. "snacks.nvim"
---@return string
function M.dir(name)
  return dir_of({ name = name })
end

--- Prepend each plugin to the runtimepath, so it wins over anything already there.
---@param ... string plugin names
function M.add(...)
  for _, name in ipairs({ ... }) do
    vim.opt.runtimepath:prepend(M.dir(name))
  end
end

return M
