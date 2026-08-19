-- The left column: the neo-tree file tree with the symbols outline stacked
-- beneath it. edgy owns the stacking and sizing (see lua/plugins/edgy.lua); this
-- module owns "is it open, open it, close it".
--
-- Split out of plugins/explorer.lua because config/workspace.lua needs the same
-- open() when it sets a tabpage up as a project workspace -- opening a sidebar is
-- no longer something only the startup handler does.
--
-- Everything here is per-tabpage: neo-tree keys its state by tabpage, and the
-- window searches below only ever look at the current one, so each workspace tab
-- gets its own tree rooted at that tab's cwd.

local M = {}

--- The window in this tabpage showing neo-tree `source`, or nil.
---@param source string
---@return integer?
function M.win(source)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    local ok, src = pcall(vim.api.nvim_buf_get_var, buf, "neo_tree_source")
    if ok and src == source then
      return win
    end
  end
end

-- Open the file tree and the outline; edgy stacks them in the left edgebar.
-- `show` reveals without focusing, so this is safe to call from auto-open.
-- document_symbols opens at a neutral position so neo-tree doesn't replace the
-- filesystem window before edgy moves it -- the old "two explorers" collision.
function M.open()
  vim.cmd("Neotree filesystem show left")
  if not M.win("document_symbols") then
    vim.cmd("Neotree document_symbols show bottom")
  end
end

-- Close every neo-tree window in the tabpage (both the tree and the outline; the
-- outline lives in a plain split, so :Neotree close alone wouldn't get it).
function M.close()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if pcall(vim.api.nvim_buf_get_var, buf, "neo_tree_source") then
      pcall(vim.api.nvim_win_close, win, false)
    end
  end
end

function M.toggle()
  if M.win("filesystem") or M.win("document_symbols") then
    M.close()
  else
    M.open()
  end
end

return M
