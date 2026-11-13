-- The workspaces each nvim has open, kept on disk so a restart can bring them back with their Claude sessions.
--
-- One file shared by every nvim (terminal and Neovide), keyed by project
-- directory: a save merges this nvim's projects in and drops only the ones this
-- nvim closed, so two editors never wipe each other's entries.

local M = {}

---@class workspace_state.Project
---@field slot? integer the workspace number it had, for a stable restore order
---@field session? string terminal 1's Claude session id

---@alias workspace_state.Projects table<string, workspace_state.Project> project dir -> project

---@class workspace_state.Options
---@field file string where the projects are kept
---@field claude_projects string Claude's projects directory, holding each session's transcript
local options = {
  file = vim.fn.stdpath("state") .. "/workspaces.json",
  claude_projects = vim.fn.expand("~/.claude/projects"),
}

-- The dirs this nvim held at its last save: one gone from its tabs since was closed here.
local mine = {}
-- Set from VimLeavePre on: tabs and agents vanishing during exit aren't closes.
local leaving = false

local collect, load, write, forget, valid_session, real

--- Set once at startup (init.lua): watch the workspaces and add :WorkspaceRestore.
---@param opts? workspace_state.Options
function M.setup(opts)
  options = vim.tbl_extend("force", options, opts or {})
  mine, leaving = {}, false
  local group = vim.api.nvim_create_augroup("workspace_state", { clear = true })
  local queued = false
  local function queue_save()
    if queued then
      return
    end
    queued = true
    vim.schedule(function()
      queued = false
      M.save()
    end)
  end
  vim.api.nvim_create_autocmd({ "TabNewEntered", "TabClosed", "DirChanged" }, {
    group = group,
    callback = queue_save,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "FishmongerTabsChanged", "WorkspaceRenumbered" },
    callback = queue_save,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      M.save()
      leaving = true
    end,
  })
  vim.api.nvim_create_user_command("WorkspaceRestore", function()
    M.restore()
  end, { desc = "Reopen every saved workspace not open here, resuming its Claude" })
end

--- Merge this nvim's workspaces into the file.
function M.save()
  if leaving then
    return
  end
  local now = collect()
  local stored = load()
  local merged = M.next_state(stored, mine, now)
  mine = {}
  for dir in pairs(now) do
    mine[dir] = true
  end
  if merged then
    write(merged)
  end
end

--- Reopen every saved project not open here, each resuming its Claude session;
--- a project whose directory is gone is dropped from the file.
---@param opts? { drop_buf?: integer } take over the current tabpage (the dashboard's) for the first one
function M.restore(opts)
  opts = opts or {}
  local workspace = require("config.workspace")
  local plan = M.restorable(load(), function(dir)
    return workspace.find(dir) ~= nil
  end, function(dir)
    return vim.fn.isdirectory(dir) == 1
  end)
  local drop_buf = opts.drop_buf
  for _, p in ipairs(plan.open) do
    workspace.open(p.dir, {
      tab = drop_buf == nil,
      drop_buf = drop_buf,
      background = drop_buf == nil,
      slot = p.slot,
      resume = M.resume_id(p.session, options.claude_projects),
    })
    drop_buf = nil
  end
  if #plan.gone > 0 then
    forget(plan.gone)
    vim.notify("gone, so not resumed: " .. table.concat(plan.gone, ", "), vim.log.levels.WARN)
  elseif #plan.open == 0 then
    vim.notify("no saved workspaces to resume", vim.log.levels.INFO)
  end
end

--- What the file should hold after this nvim's save, or nil when nothing needs writing.
---@param stored workspace_state.Projects the file as it is now
---@param mine_before table<string, true> the dirs this nvim held at its last save
---@param now workspace_state.Projects this nvim's workspaces
---@return workspace_state.Projects?
function M.next_state(stored, mine_before, now)
  local merged = vim.deepcopy(stored)
  for dir in pairs(mine_before) do
    if not now[dir] then
      merged[dir] = nil
    end
  end
  for dir, p in pairs(now) do
    -- An agent gone quiet (dying before nvim at a shutdown) still has a conversation to resume.
    local session = p.session or (stored[dir] and stored[dir].session)
    merged[dir] = { slot = p.slot, session = session }
  end
  if vim.deep_equal(merged, stored) then
    return nil
  end
  return merged
end

---@class workspace_state.Restorable: workspace_state.Project
---@field dir string

--- Which saved projects to reopen, in workspace-number order, and which are gone from disk.
---@param stored workspace_state.Projects
---@param is_open fun(dir: string): boolean
---@param is_dir fun(dir: string): boolean
---@return { open: workspace_state.Restorable[], gone: string[] }
function M.restorable(stored, is_open, is_dir)
  local plan = { open = {}, gone = {} }
  for _, dir in ipairs(vim.fn.sort(vim.tbl_keys(stored))) do
    if not is_dir(dir) then
      plan.gone[#plan.gone + 1] = dir
    elseif not is_open(dir) then
      local p = stored[dir]
      plan.open[#plan.open + 1] = { dir = dir, slot = p.slot, session = p.session }
    end
  end
  table.sort(plan.open, function(a, b)
    return (a.slot or math.huge) < (b.slot or math.huge)
  end)
  return plan
end

--- `session` when Claude still has its transcript, so terminal 1 resumes it rather than failing to.
---@param session? string
---@param projects string Claude's projects directory
---@return string?
function M.resume_id(session, projects)
  if not session then
    return nil
  end
  -- Session ids are unique, so any project's directory may hold it.
  local found = vim.fn.glob(projects .. "/*/" .. session .. ".jsonl", true, true)
  return #found > 0 and session or nil
end

--- This nvim's workspaces: each tabpage with a workspace number, and terminal 1's Claude session.
---@return workspace_state.Projects
function collect()
  local workspace = require("config.workspace")
  local fishmonger = package.loaded["fishmonger"]
  local now = {}
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local slot = workspace.slot(tab)
    if slot then
      local session
      for _, term in ipairs(fishmonger and fishmonger.tabs(tab) or {}) do
        if term.slot == 1 and term.agent then
          session = valid_session(term.agent.session)
        end
      end
      now[real(workspace.cwd(tab))] = { slot = slot, session = session }
    end
  end
  return now
end

--- The file's projects, keeping only well-formed entries.
---@return workspace_state.Projects
function load()
  local f = io.open(options.file, "r")
  if not f then
    return {}
  end
  local ok, data = pcall(vim.json.decode, f:read("*a"))
  f:close()
  local projects = {}
  for dir, p in pairs(ok and type(data) == "table" and data or {}) do
    if type(dir) == "string" and type(p) == "table" then
      projects[dir] = {
        slot = type(p.slot) == "number" and p.slot % 1 == 0 and p.slot or nil,
        session = valid_session(p.session),
      }
    end
  end
  return projects
end

--- Replace the file in one rename, so a crash mid-write leaves the old one whole.
---@param projects workspace_state.Projects
function write(projects)
  vim.fn.mkdir(vim.fs.dirname(options.file), "p")
  local tmp = options.file .. ".tmp." .. vim.fn.getpid()
  local f = io.open(tmp, "w")
  if not f then
    return
  end
  f:write(vim.json.encode(vim.tbl_isempty(projects) and vim.empty_dict() or projects))
  f:close()
  vim.uv.fs_rename(tmp, options.file)
end

--- Drop `dirs` from the file.
---@param dirs string[]
function forget(dirs)
  local stored = load()
  for _, dir in ipairs(dirs) do
    stored[dir] = nil
  end
  write(stored)
end

--- `id` if it is a session id, which also makes it safe to put in a shell command.
---@param id any
---@return string?
function valid_session(id)
  return type(id) == "string" and id:match("^%x+%-%x+%-%x+%-%x+%-%x+$") and id or nil
end

---@param path string
---@return string
function real(path)
  return vim.uv.fs_realpath(path) or path
end

return M
