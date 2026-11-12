-- The personal todo list (plugins/checkmate.lua) as a split under a window,
-- shown by the greeter (config/greeter.lua).
local M = {}

-- Outside the dotfiles: the repo is public.
M.FILE = vim.fs.normalize("~/todo.md")

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
  -- Unlisted (bufadd's default), so config.windows never routes a file into
  -- this split. A missing file is a new buffer that the first save creates.
  local todo_win = vim.api.nvim_open_win(vim.fn.bufadd(path), false, {
    split = "below",
    win = win,
    height = math.max(6, math.floor(vim.api.nvim_win_get_height(win) / 3)),
  })
  vim.wo[todo_win].winfixheight = true
  return todo_win
end

return M
