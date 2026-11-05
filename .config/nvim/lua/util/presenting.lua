-- Presenting: with someone watching, drop the training wheels -- hardtime off and
-- the mouse on for pointing -- then back to keyboard-only afterwards.

local M = {}

---@class presenting.Hardtime
---@field is_plugin_enabled boolean
---@field enable fun()
---@field disable fun()

--- Is presenting on? Read off hardtime, so `:Hardtime toggle` can't desync it.
---@param hardtime presenting.Hardtime
---@return boolean
function M.is_on(hardtime)
  return not hardtime.is_plugin_enabled
end

---@param hardtime presenting.Hardtime
---@param on boolean
function M.set(hardtime, on)
  if on then
    hardtime.disable()
  else
    hardtime.enable()
  end
  vim.o.mouse = on and "a" or ""
end

return M
