-- The parsers the nvim under test ships come with their highlight queries: checked in
-- a child with an empty data dir, so queries an old install left there can't stand in.

local assert = require("luassert")
local plugins = require("tests.helpers.plugins")

--- Runs `lua` in a child nvim with the full config and a fresh data dir; returns its stdout as JSON.
---@param lua string
---@param file string|nil opened before `lua` runs
---@return any
local function in_fresh_nvim(lua, file)
  local env = vim.fn.environ()
  for _, name in ipairs({ "NVIM", "VIM", "VIMRUNTIME" }) do
    env[name] = nil
  end
  env.XDG_DATA_HOME = vim.fn.tempname()
  local cmd = { plugins.nvim(), "--headless" }
  if file then
    table.insert(cmd, file)
  end
  vim.list_extend(cmd, { "-c", "lua io.stdout:write(vim.json.encode((function() " .. lua .. " end)()))", "-c", "qa!" })
  local res = vim.system(cmd, { env = env, clear_env = true, text = true }):wait(60000)
  vim.fn.delete(env.XDG_DATA_HOME, "rf")
  assert.equals(0, res.code, res.stderr)
  return vim.json.decode(res.stdout)
end

describe("treesitter in the nvim under test", function()
  it("has a highlights query for every parser it ships", function()
    local result = in_fresh_nvim([[
      local languages, missing = {}, {}
      for _, path in ipairs(vim.api.nvim_get_runtime_file("parser/*.so", true)) do
        local language = vim.fn.fnamemodify(path, ":t:r")
        languages[#languages + 1] = language
        if not vim.treesitter.query.get(language, "highlights") then
          missing[#missing + 1] = language
        end
      end
      return { languages = languages, missing = missing }
    ]])
    assert.is_true(vim.tbl_contains(result.languages, "nix"), vim.inspect(result.languages))
    assert.same({}, result.missing)
  end)
end)
