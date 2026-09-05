local M = {}

-- Route the git-TUI keys to the right tool for a given repo: jjui in a jj repo,
-- lazygit otherwise. Colocated repos carry both .jj and .git; we treat those as
-- jj, since a repo with jj set up at all is one we drive through jj.
--
-- `dir` defaults to the current file's directory (so we detect correctly inside
-- a polyrepo tree, not just at nvim's cwd), falling back to the cwd for unnamed
-- buffers and terminals.
---@param dir? string
local function driver(dir)
  if not dir then
    local buf = vim.api.nvim_buf_get_name(0)
    dir = (buf ~= "" and vim.fs.dirname(buf)) or (vim.uv or vim.loop).cwd()
  end
  if vim.fs.root(dir, ".jj") then
    return require("util.jjui")
  end
  return require("util.lazygit")
end

-- <C-g>: toggle the git TUI for wherever the cursor is. A second press closes it
-- (each module toggles). Works from normal and terminal mode.
function M.open()
  driver().open()
end

-- <C-S-g>: pick a project and open its git TUI, for driving a repo other than
-- nvim's cwd (e.g. within a polyrepo tree). Dispatch is per *chosen* project, so
-- picking a jj repo opens jjui even from a git repo and vice versa.
function M.pick()
  -- Hide any open float first: WinLeave doesn't reliably fire when the picker
  -- grabs focus, so an existing TUI would otherwise linger over the picker. We
  -- don't know which is up, so hide both.
  require("util.jjui").hide()
  require("util.lazygit").hide()
  Snacks.picker.projects({
    confirm = function(picker, item)
      picker:close()
      if item and item.file then
        -- schedule so the picker window is fully torn down before the TUI
        -- terminal float takes focus.
        vim.schedule(function()
          driver(item.file).float(item.file)
        end)
      end
    end,
  })
end

--- The workspace-tab backend for a repo: jj workspaces in a jj repo, git
--- worktrees otherwise. Same rule as driver() above -- a colocated repo carries
--- both .jj and .git, and jj wins, because git worktrees and jj workspaces are
--- not interchangeable and a repo with jj set up is one we drive through jj.
---@param dir? string default: the tab's cwd
---@return table
local function tabs(dir)
  dir = dir or vim.fn.getcwd()
  if vim.fs.root(dir, ".jj") then
    return require("util.jjworkspace")
  end
  return require("util.worktree")
end

--- <leader>tw: pick a branch/bookmark and open it as its own workspace tab.
function M.pick_tab()
  tabs().pick()
end

--- <leader>tf: fork the current workspace tab.
function M.fork_tab()
  tabs().fork()
end

return M
