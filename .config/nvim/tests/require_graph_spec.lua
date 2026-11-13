-- The config's own modules must not depend on each other in a circle.

local assert = require("luassert")

local lua_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/lua"

-- Every way a module reaches another by name, lazy ones included.
local reference_patterns = {
  "require%s*%(?%s*[\"']([%w_.%-]+)[\"']",
  "pcall%(%s*require%s*,%s*[\"']([%w_.%-]+)[\"']",
  "package%.loaded%[%s*[\"']([%w_.%-]+)[\"']%s*%]",
}

--- Module name -> the set of the config's own modules it references.
---@return table<string, table<string, true>>
local function require_graph()
  local graph = {}
  for path, kind in vim.fs.dir(lua_dir, { depth = math.huge }) do
    if kind == "file" and path:match("%.lua$") then
      graph[path:gsub("%.lua$", ""):gsub("/init$", ""):gsub("/", ".")] = {}
    end
  end
  for name in pairs(graph) do
    local file = lua_dir .. "/" .. name:gsub("%.", "/") .. ".lua"
    for _, line in ipairs(vim.fn.readfile(file)) do
      local code = line:gsub("%-%-.*$", "")
      for _, pattern in ipairs(reference_patterns) do
        for target in code:gmatch(pattern) do
          if graph[target] and target ~= name then
            graph[name][target] = true
          end
        end
      end
    end
  end
  return graph
end

--- Every cycle a depth-first walk closes, each as "a -> b -> a".
---@param graph table<string, table<string, true>>
---@return string[]
local function cycles(graph)
  local found, state, stack = {}, {}, {}
  local function visit(name)
    state[name] = "open"
    stack[#stack + 1] = name
    for _, target in ipairs(vim.fn.sort(vim.tbl_keys(graph[name]))) do
      if state[target] == "open" then
        local from = vim.fn.index(stack, target) + 1
        found[#found + 1] = table.concat(vim.list_slice(stack, from), " -> ") .. " -> " .. target
      elseif not state[target] then
        visit(target)
      end
    end
    stack[#stack] = nil
    state[name] = "done"
  end
  for _, name in ipairs(vim.fn.sort(vim.tbl_keys(graph))) do
    if not state[name] then
      visit(name)
    end
  end
  return found
end

describe("the require graph under lua/", function()
  it("sees a lazy require inside a function as an edge", function()
    assert.is_true(require_graph()["util.worktree"]["config.workspace"])
  end)

  it("has no cycles", function()
    assert.same({}, cycles(require_graph()))
  end)
end)
