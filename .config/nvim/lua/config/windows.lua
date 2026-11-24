-- Main-editor-window routing, shared by the file-opening keymaps (gf/gp),
-- buffer switching (<S-l>/<S-h>, bufferline clicks), the greeter and the
-- pickers, so nothing ever opens a file over the side terminal or the explorer.
local M = {}

-- Buffer role: stands in for the main window wherever it is shown (the greeter).
local PLACEHOLDER = "main_placeholder"
-- Window role: a split under the main window that anything but the greeter there puts away (the todo list);
-- holds the buffer it was opened for and the window it sits under.
local COMPANION = "main_companion"
-- Window mark: held at its placeholder's height beside its companions (see M.hold_height).
local HELD = "main_held"

local is_file, move_file, sits_under, release

--- Put companions away for whatever takes the window they sit under, and a file opened in one into the main window.
function M.setup()
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = vim.api.nvim_create_augroup("main_companions", { clear = true }),
    callback = function(ev)
      local win = vim.api.nvim_get_current_win()
      if vim.w[win][COMPANION] == nil then
        -- Now: what arrived may split windows under it (an agent chat's prompt) that a later close would grow.
        return M.replace_placeholders(win)
      end
      -- Deferred: moving the file out closes the window the opening command is still in.
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == ev.buf then
          M.replace_placeholders(win)
        end
      end)
    end,
  })
end

--- The buffer now in `win`: anything but the greeter in the window a companion sits under closes the tab's
--- companions, and a file in a companion moves to the main window first.
---@param win integer
function M.replace_placeholders(win)
  local tab = vim.api.nvim_win_get_tabpage(win)
  local buf = vim.api.nvim_win_get_buf(win)
  local own = vim.w[win][COMPANION]
  if own ~= nil then
    if own.buf == buf or not is_file(buf) then
      return
    end
    local main = M.main_window(tab)
    if not main then
      -- The companion is all the main area this tab has, so it becomes the main window.
      vim.w[win][COMPANION] = nil
      return
    end
    move_file(win, main)
    release(main)
  elseif vim.b[buf][PLACEHOLDER] then
    return
  else
    release(win)
    if not sits_under(tab, win) then
      return
    end
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

--- Hold `win`, showing a placeholder, at `height` rows while a companion sits under it; anything else shown in it lets go.
---@param win integer
---@param height integer
function M.hold_height(win, height)
  if not sits_under(vim.api.nvim_win_get_tabpage(win), win) then
    return
  end
  vim.api.nvim_win_set_height(win, height)
  vim.wo[win].winfixheight = true
  vim.w[win][HELD] = true
end

--- Mark `win` as a companion of main window `under`, standing for the buffer it shows now.
---@param win integer
---@param under integer
function M.mark_companion(win, under)
  vim.w[win][COMPANION] = { buf = vim.api.nvim_win_get_buf(win), under = under }
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

--- Edit `path` in the main window, with the cursor at `line` and `col` (both 1-based) when given.
---@param path string
---@param line? integer
---@param col? integer
function M.open(path, line, col)
  M.goto_main_window()
  vim.cmd.edit(vim.fn.fnameescape(path))
  if line then
    local last = vim.api.nvim_buf_line_count(0)
    vim.api.nvim_win_set_cursor(
      0,
      { math.min(math.max(line, 1), last), math.max((col or 1) - 1, 0) }
    )
  end
end

--- Show `from`'s buffer in `to` where `from` had it scrolled, taking focus along if `from` had it.
---@param from integer
---@param to integer
function move_file(from, to)
  local view = vim.api.nvim_win_call(from, vim.fn.winsaveview)
  vim.api.nvim_win_set_buf(to, vim.api.nvim_win_get_buf(from))
  vim.api.nvim_win_call(to, function()
    vim.fn.winrestview(view)
  end)
  if vim.api.nvim_get_current_win() == from then
    vim.api.nvim_set_current_win(to)
  end
end

--- Whether a companion in `tab` sits under `win`.
---@param tab integer
---@param win integer
---@return boolean
function sits_under(tab, win)
  return vim.iter(M.companions(tab)):any(function(companion)
    return vim.w[companion][COMPANION].under == win
  end)
end

--- Let go of the height a placeholder held `win` at: what replaced it has the window to itself.
---@param win integer
function release(win)
  if vim.w[win][HELD] then
    vim.w[win][HELD] = nil
    vim.wo[win].winfixheight = false
  end
end

--- An ordinary, listed file buffer.
---@param buf integer
---@return boolean
function is_file(buf)
  return vim.bo[buf].buftype == "" and vim.bo[buf].buflisted
end

return M
