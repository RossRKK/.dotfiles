-- Main-editor-window routing, shared by the file-opening keymaps (gf/gp) and
-- buffer switching (<S-l>/<S-h>, bufferline clicks) so nothing ever opens a
-- file over the terminal or the explorer.
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

--- The tabpage's main editor window: the first window holding an ordinary file
--- buffer (or the greeter). nil if the tab is all panels.
---@param tab? integer tabpage handle (default: current)
---@return integer?
function M.main_window(tab)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab or 0)) do
    if M.is_editor_window(win) then
      return win
    end
  end
end

-- Ensure the current window is a main editor window before opening a file.
-- Reuses an existing editor window if there is one. Never splits: splitting the
-- terminal (or a diagnostic float) to make a window just leaves a stray,
-- wrong-width split. If no editor window exists at all, we fall through and
-- stay in the current window.
function M.goto_main_window()
  if M.is_editor_window(vim.api.nvim_get_current_win()) then
    return
  end
  vim.cmd("stopinsert") -- no-op unless we're in terminal insert mode
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if M.is_editor_window(win) then
      vim.api.nvim_set_current_win(win)
      return
    end
  end
end

return M
