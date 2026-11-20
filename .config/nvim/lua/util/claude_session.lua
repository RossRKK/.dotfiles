-- Claude Code's record of each live session, <config dir>/sessions/<pid>.json, read for the name it goes by,
-- and of each session's transcript, read for the directory it ran in.

local M = {}

--- The name the Claude running as `pid` goes by (its /rename title), or nil when it has none.
---@param sessions string Claude's sessions directory
---@param pid integer the claude process
---@return string?
function M.name(sessions, pid)
  local f = io.open(sessions .. "/" .. pid .. ".json", "r")
  if not f then
    return nil
  end
  local ok, record = pcall(vim.json.decode, f:read("*a"))
  f:close()
  local name = ok and type(record) == "table" and record.name
  return type(name) == "string" and name ~= "" and name or nil
end

--- The standing role terminal 1's Claude takes in `dir`, as the session-identity
--- mod's role-name reads it: the first "<checkout> <role>" line naming `dir`.
---@param roles string the claude-roles file
---@param dir string
---@return string?
function M.role(roles, dir)
  local f = io.open(roles, "r")
  if not f then
    return nil
  end
  local here = vim.uv.fs_realpath(dir) or dir
  local found
  for line in f:lines() do
    local checkout, role = line:match("^%s*(%S+)%s+(.-)%s*$")
    local path = checkout and vim.fs.normalize(checkout)
    if role and role ~= "" and (vim.uv.fs_realpath(path) or path) == here then
      found = role
      break
    end
  end
  f:close()
  return found
end

--- The directory session `id` started in, as its transcript's first row with one
--- records it: Claude files the transcript under it, so a resume has to run there.
---@param projects string Claude's projects directory
---@param id string
---@return string?
function M.cwd(projects, id)
  -- Session ids are unique, so any project's directory may hold it.
  local transcript = vim.fn.glob(projects .. "/*/" .. id .. ".jsonl", true, true)[1]
  if not transcript then
    return nil
  end
  for line in io.lines(transcript) do
    local ok, row = pcall(vim.json.decode, line)
    if ok and type(row) == "table" and type(row.cwd) == "string" then
      return row.cwd
    end
  end
end

return M
