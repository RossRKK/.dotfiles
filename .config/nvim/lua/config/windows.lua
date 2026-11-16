-- Main-editor-window routing, shared by the file-opening keymaps (gf/gp),
-- buffer switching (<S-l>/<S-h>, bufferline clicks), the greeter and the
-- pickers, so nothing ever opens a file over the side terminal or the explorer.
local M = {}

-- Buffer role: stands in for the main window wherever it is shown (the greeter).
local PLACEHOLDER = "main_placeholder"
-- Window role: a split beside the main window that a file puts away (the todo list); holds the buffer it was opened for.
local COMPANION = "main_companion"

local is_file

--- Put a tab's companion windows away whenever a file opens in its main window.
function M.setup()
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = vim.api.nvim_create_augroup("main_companions", { clear = true }),
    callback = function(ev)
      local win = vim.api.nvim_get_current_win()
      -- Deferred: closing a window mid-command pulls the layout from under it.
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == ev.buf then
          M.replace_placeholders(win)
        end
      end)
    end,
  })
end

--- If `win` holds a file and is its tab's main window, close the tab's companions.
---@param win integer
function M.replace_placeholders(win)
  local tab = vim.api.nvim_win_get_tabpage(win)
  if not is_file(vim.api.nvim_win_get_buf(win)) or win ~= M.main_window(tab) then
    return
  end
  for _, companion in ipairs(M.companions(tab)) do
    vim.api.nvim_win_close(companion, false)
  end
end

--- Mark `buf` as a placeholder: files open over it, whichever window shows it.
---@param buf integer
function M.mark_placeholder(buf)
  vim.b[buf][PLACEHOLDER] = true
end

--- Mark `win` as a companion of the main window, standing for the buffer it shows now.
---@param win integer
function M.mark_companion(win)
  vim.w[win][COMPANION] = vim.api.nvim_win_get_buf(win)
end

--- The companion windows in `tab`.
---@param tab integer tabpage handle (0: current)
---@return integer[]
function M.companions(tab)
  return vim.tbl_filter(function(win)
    return vim.w[win][COMPANION] ~= nil
  end, vim.api.nvim_tabpage_list_wins(tab))
end

-- A window is a "main" editor window only if it positively holds an ordinary,
-- listed file buffer. This is an allowlist on purpose: anything else — the
-- terminal, the neo-tree explorer, and every floating/scratch menu (Lazy's
-- update UI, help peeks, quickfix) — is not a target, without having to name it.
function M.is_editor_window(win)
  -- Floats (Lazy, notifications, help peeks) and companion splits are never editor targets.
  if vim.api.nvim_win_get_config(win).relative ~= "" or vim.w[win][COMPANION] ~= nil then
    return false
  end
  local buf = vim.api.nvim_win_get_buf(win)
  -- A placeholder is unlisted or nofile, but it IS the main window whenever it's showing.
  return vim.b[buf][PLACEHOLDER] == true or is_file(buf)
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

--- Where a file meant for `candidate` (an opener's own pick) should open: there if it is an editor window, else the main window.
---@param candidate integer
---@return integer?
function M.target_window(candidate)
  if vim.api.nvim_win_is_valid(candidate) and M.is_editor_window(candidate) then
    return candidate
  end
  return M.main_window()
end

-- Ensure the current window is a main editor window before opening a file.
-- Never splits: splitting the terminal (or a diagnostic float) to make a window
-- just leaves a stray, wrong-width split. If there is no main window at all, we
-- stay in the current window.
function M.goto_main_window()
  local current = vim.api.nvim_get_current_win()
  local win = M.target_window(current)
  if not win or win == current then
    return
  end
  vim.cmd("stopinsert") -- no-op unless we're in terminal insert mode
  vim.api.nvim_set_current_win(win)
end

--- An ordinary, listed file buffer.
---@param buf integer
---@return boolean
function is_file(buf)
  return vim.bo[buf].buftype == "" and vim.bo[buf].buflisted
end

return M
