-- Main-editor-window routing, shared by the file-opening keymaps (gf/gp) and
-- buffer switching (<S-l>/<S-h>, bufferline clicks) so nothing ever opens a
-- file over the side terminal or the explorer.
local M = {}

-- A window is a "main" editor window only if it positively holds an ordinary,
-- listed file buffer. This is an allowlist on purpose: anything else — the
-- terminal, the neo-tree explorer, and every floating/scratch menu (Lazy's
-- update UI, help peeks, quickfix) — is not a target, without having to name it.
function M.is_editor_window(win)
  -- Floating windows (Lazy, notifications, help peeks) are never editor targets.
  if vim.api.nvim_win_get_config(win).relative ~= "" then
    return false
  end
  local buf = vim.api.nvim_win_get_buf(win)
  -- The workspace greeter (config/greeter.lua) is unlisted nofile, but it IS
  -- the main window whenever it's showing — files must open over it.
  if vim.bo[buf].filetype == "snacks_dashboard" then
    return true
  end
  return vim.bo[buf].buftype == "" and vim.bo[buf].buflisted
end

--- A terminal standing in the main area (<C-b>t) rather than docked as the side
--- panel. Files open over it: the shell lives on hidden, a <C-b> key away.
---@param win integer
---@return boolean
function M.is_main_terminal(win)
  return vim.api.nvim_win_get_config(win).relative == ""
    and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "terminal"
    and not vim.w[win].fishmonger_side
end

---@param tab integer
---@param accept fun(win: integer): boolean
---@return integer?
local function first_window(tab, accept)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if accept(win) then
      return win
    end
  end
end

--- The tabpage's main editor window: the first window holding an ordinary file
--- buffer (or the greeter), else a terminal in the main area. nil if the tab is
--- all panels.
---@param tab? integer tabpage handle (default: current)
---@return integer?
function M.main_window(tab)
  tab = tab or 0
  return first_window(tab, M.is_editor_window) or first_window(tab, M.is_main_terminal)
end

-- Ensure the current window is a main editor window before opening a file.
-- Never splits: splitting the terminal (or a diagnostic float) to make a window
-- just leaves a stray, wrong-width split. If there is no main window at all, we
-- stay in the current window.
function M.goto_main_window()
  if M.is_editor_window(vim.api.nvim_get_current_win()) then
    return
  end
  vim.cmd("stopinsert") -- no-op unless we're in terminal insert mode
  local win = M.main_window()
  if win then
    vim.api.nvim_set_current_win(win)
  end
end

return M
