-- The nvim under test keeps Lua's default search paths, so Lua run from it, or
-- from its terminals, still finds ./?.lua modules (plugin test suites rely on it).

local assert = require("luassert")
local plugins = require("tests.helpers.plugins")

--- package.path and package.cpath in a child nvim started without LUA_PATH/LUA_CPATH.
---@return { path: string, cpath: string }
local function search_paths()
  local env = vim.fn.environ()
  for _, name in ipairs({ "NVIM", "VIM", "VIMRUNTIME", "LUA_PATH", "LUA_CPATH" }) do
    env[name] = nil
  end
  local res = vim
    .system({
      plugins.nvim(),
      "--headless",
      "--clean",
      "-c",
      "lua io.stdout:write(vim.json.encode({ path = package.path, cpath = package.cpath }))",
      "-c",
      "qa!",
    }, { env = env, clear_env = true, text = true })
    :wait(30000)
  assert.equals(0, res.code, res.stderr)
  return vim.json.decode(res.stdout)
end

describe("the nvim under test", function()
  it("keeps Lua's default search paths", function()
    local paths = search_paths()
    assert.truthy(paths.path:find("./?.lua", 1, true), paths.path)
    assert.truthy(paths.cpath:find("./?.so", 1, true), paths.cpath)
  end)
end)
