-- The header of snacks.nvim's gh:// buffers, trimmed and joined up: no Repo or
-- Changes lines, one line for when the PR was opened and updated, and one for
-- whether and how it can merge. Snacks has no option for the header's fields,
-- so this edits its public props table (snacks.gh.render.props).

local M = {}

local patched = false
local joined

--- Patch snacks' gh header once; snacks asks for its gh config more than once.
function M.apply()
  if patched then
    return
  end
  M.patch(require("snacks.gh.render").props)
  patched = true
end

--- Reshape snacks' header `props` in place, each joined line where its first
--- part was. An error when a prop it names is gone (a snacks update), rather
--- than a header that quietly stops matching.
---@param props { name: string, hl: fun(item: table, opts: table): table[]? }[]
function M.patch(props)
  local function take(name)
    for i, prop in ipairs(props) do
      if prop.name == name then
        return table.remove(props, i), i
      end
    end
    error(("snacks gh header: no %q prop to patch"):format(name), 0)
  end
  take("Repo")
  take("Changes")
  local created, at = take("Created")
  table.insert(props, at, joined("Opened", created, take("Updated"), " · updated "))
  local status, status_at = take("Merge Status")
  table.insert(props, status_at, joined("Merge", take("Mergeable"), status, " · "))
end

--- A prop showing `first` and `second`'s values on one line, `sep` between
--- them, either alone when the other has nothing, and no line for neither.
---@param name string
---@param first { hl: fun(item: table, opts: table): table[]? }
---@param second { hl: fun(item: table, opts: table): table[]? }
---@param sep string
function joined(name, first, second, sep)
  return {
    name = name,
    hl = function(item, opts)
      local a, b = first.hl(item, opts), second.hl(item, opts)
      a, b = a and #a > 0 and a or nil, b and #b > 0 and b or nil
      if a and b then
        return vim.list_extend(
          vim.list_extend(vim.list_extend({}, a), { { sep, "SnacksGhDelim" } }),
          b
        )
      end
      return a or b
    end,
  }
end

return M
