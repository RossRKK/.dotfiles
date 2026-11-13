-- Claude Code's record of each live session, <config dir>/sessions/<pid>.json, read for the name it goes by.

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

return M
