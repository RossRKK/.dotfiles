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

-- Close the docked neo-tree window. The outline float is left alone -- it
-- closes on its own.
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
  if M.win("filesystem") then
    M.close()
  else
    M.open()
  end
end

-- Markers for "the project a file belongs to" when it sits outside the workspace.
local project_markers = { "Cargo.toml", "go.mod", "package.json", "pyproject.toml", ".git" }

---@alias sidebar.RevealTarget
---| { kind: "tree" } reveal in the docked tree, which stays rooted at the workspace
---| { kind: "float", root: string } browse `root` in a float, leaving the tree alone

--- Where <leader>v should show `file` from a workspace rooted at `workspace`.
---@param file string? absolute path of the current buffer, nil when it has none
---@param workspace string
---@return sidebar.RevealTarget
function M.reveal_target(file, workspace)
  if not file or vim.fs.relpath(workspace, file) then
    return { kind = "tree" }
  end
  return { kind = "float", root = vim.fs.root(file, project_markers) or vim.fs.dirname(file) }
end

--- Show the current file in context without ever re-rooting the docked tree: a
--- file outside the workspace (a crate in ~/.cargo) opens a float of its project.
function M.reveal()
  local workspace = vim.fn.getcwd(-1, 0)
  local name = vim.api.nvim_buf_get_name(0)
  local file = vim.bo.buftype == "" and name ~= "" and vim.fs.normalize(name) or nil
  local target = M.reveal_target(file, workspace)
  if target.kind == "tree" then
    -- dir pins the root (and restores it if it was navigated away) and makes
    -- neo-tree skip its "change cwd?" prompt.
    require("neo-tree.command").execute({ source = "filesystem", position = "left", reveal = true, dir = workspace })
  else
    Snacks.picker.explorer({
      cwd = target.root,
      title = vim.fn.fnamemodify(target.root, ":~"),
      auto_close = true,
      layout = { preset = "dropdown", preview = false },
    })
  end
end

return M
