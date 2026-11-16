-- The personal todo list (plugins/checkmate.lua) as a split under a tab's main
-- window: shown by the greeter (config/greeter.lua) or toggled by hand, and put
-- away when a file takes the main window over (a companion, config/windows.lua).
local M = {}

-- Outside the dotfiles: the repo is public.
M.FILE = vim.fs.normalize("~/todo.md")

--- Close the tab's todo split if it has one, else open it under the main window
--- and focus it.
---@param path string the todo file
function M.toggle(path)
  local shown = M.window(0, path)
  if shown then
    vim.api.nvim_win_close(shown, false)
    return
  end
  local anchor = require("config.windows").main_window(0) or M.fallback_anchor()
  if not anchor then
    vim.notify("No window to open the todo list under", vim.log.levels.WARN)
    return
  end
  vim.api.nvim_set_current_win(M.open_below(anchor, path))
end

--- The window in `tab` showing the todo list, or nil.
---@param tab integer tabpage handle (0: current)
---@param path string the todo file
---@return integer?
function M.window(tab, path)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if vim.fs.normalize(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))) == path then
      return win
    end
  end
end

--- Open the todo list in a split below `win`, without focusing it. Below rather
--- than beside, as the greeter above it needs its full width.
---@param win integer
---@param path string the todo file
---@return integer the todo window
function M.open_below(win, path)
  -- A missing file is a new buffer that the first save creates.
  local todo_win = vim.api.nvim_open_win(vim.fn.bufadd(path), false, {
    split = "below",
    win = win,
    height = math.max(6, math.floor(vim.api.nvim_win_get_height(win) / 3)),
  })
  vim.wo[todo_win].winfixheight = true
  require("config.windows").mark_companion(todo_win)
  return todo_win
end

--- Where the list goes in a tab with no main window: the current window, unless
--- it is a float or a side panel (the explorer, the side terminal).
---@return integer?
function M.fallback_anchor()
  local win = vim.api.nvim_get_current_win()
  local panel = vim.b[vim.api.nvim_win_get_buf(win)].neo_tree_source or vim.w[win].fishmonger_side
  if vim.api.nvim_win_get_config(win).relative == "" and not panel then
    return win
  end
end

return M
