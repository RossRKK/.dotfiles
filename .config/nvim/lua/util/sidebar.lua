-- The left column: the neo-tree file tree. edgy owns its placement and sizing
-- (see lua/plugins/edgy.lua); this module owns "is it open, open it, close it".
-- The symbols outline used to be stacked beneath the tree here; it is now a
-- float (<leader>lo in plugins/explorer.lua), so <C-h> always lands on the tree
-- and closing the main buffer can't strand a half-empty column.
--
-- Split out of plugins/explorer.lua because config/workspace.lua needs the same
-- open() when it sets a tabpage up as a project workspace -- opening a sidebar is
-- no longer something only the startup handler does.
--
-- Everything here is per-tabpage: neo-tree keys its state by tabpage, and the
-- window searches below only ever look at the current one, so each workspace tab
-- gets its own tree rooted at that tab's cwd.

local M = {}

--- The docked window in this tabpage showing neo-tree `source`, or nil.
--- Floats are skipped: the outline pops up as one and is not part of the column.
---@param source string
---@return integer?
function M.win(source)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(win).relative == "" then
      local buf = vim.api.nvim_win_get_buf(win)
      local ok, src = pcall(vim.api.nvim_buf_get_var, buf, "neo_tree_source")
      if ok and src == source then
        return win
      end
    end
  end
end

-- Open the file tree in the left edgebar. `show` reveals without focusing, so
-- this is safe to call from auto-open.
function M.open()
  vim.cmd("Neotree filesystem show left")
end

-- Close the docked neo-tree window (filesystem or git_status, which share the
-- slot). The outline float is left alone -- it closes on its own.
function M.close()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(win).relative == "" then
      local buf = vim.api.nvim_win_get_buf(win)
      if pcall(vim.api.nvim_buf_get_var, buf, "neo_tree_source") then
        pcall(vim.api.nvim_win_close, win, false)
      end
    end
  end
end

function M.toggle()
  if M.win("filesystem") or M.win("git_status") then
    M.close()
  else
    M.open()
  end
end

return M
