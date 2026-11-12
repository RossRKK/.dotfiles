-- The personal todo list (plugins/checkmate.lua) as a split under a tab's main
-- window: shown by the greeter (config/greeter.lua), and put away when a file
-- takes the main window over, as the greeter is.
local M = {}

-- Outside the dotfiles: the repo is public.
M.FILE = vim.fs.normalize("~/todo.md")

--- Close the todo split whenever a file opens in a tab's main window; it stays
--- away until the greeter shows it again.
---@param path string the todo file
function M.setup(path)
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = vim.api.nvim_create_augroup("todo_split", { clear = true }),
    callback = function(ev)
      local win = vim.api.nvim_get_current_win()
      -- A main-area terminal is a main window too, and must not close the list.
      if vim.bo[ev.buf].buftype ~= "" then
        return
      end
      -- Deferred: closing a window mid-command pulls the layout from under it.
      vim.schedule(function()
        if not (vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == ev.buf) then
          return
        end
        local tab = vim.api.nvim_win_get_tabpage(win)
        local todo_win = M.window(tab, path)
        if todo_win and win == require("config.windows").main_window(tab) then
          vim.api.nvim_win_close(todo_win, false)
        end
      end)
    end,
  })
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
