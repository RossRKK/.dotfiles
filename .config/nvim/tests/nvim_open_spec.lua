-- .local/bin/nvim-open, run for real against this nvim's own server, with the
-- modules it calls into stubbed: which opener a ref reaches, with what, and
-- what the caller is told.

local assert = require("luassert")

local config = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local script = vim.fs.normalize(config .. "/../../.local/bin/nvim-open")

--- Run nvim-open on `ref` from `dir`, as session `session` (none when nil).
--- The wait serves this nvim's RPC, so the script's call back into it lands.
local function run(ref, dir, session)
  local result
  vim.system({ script, ref }, {
    cwd = dir,
    env = { NVIM = vim.v.servername, CLAUDE_CODE_SESSION_ID = session or "" },
  }, function(r)
    result = r
  end)
  assert.is_true(vim.wait(10000, function()
    return result ~= nil
  end))
  return result
end

describe("nvim-open", function()
  local calls, jump_answer, dir

  before_each(function()
    if vim.v.servername == "" then
      vim.fn.serverstart()
    end
    calls, jump_answer = {}, "waiting"
    package.loaded["fishmonger.tour"] = {
      jump = function(args)
        calls[#calls + 1] = { jump = args }
        return jump_answer
      end,
    }
    package.loaded["config.windows"] = {
      open = function(path, line, col)
        calls[#calls + 1] = { open = { path, line, col } }
      end,
    }
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. "/src", "p")
    vim.fn.writefile({ "x" }, dir .. "/src/a.lua")
  end)

  after_each(function()
    package.loaded["fishmonger.tour"] = nil
    package.loaded["config.windows"] = nil
  end)

  it("is a Claude session's jump, its path made absolute, and says how it went", function()
    local r = run("src/a.lua:12:3", dir, "s1")

    assert.equals(0, r.code)
    assert.equals("waiting\n", r.stdout)
    assert.same(
      { { jump = { session = "s1", path = dir .. "/src/a.lua", line = 12, col = 3 } } },
      calls
    )
  end)

  it("opens straight away outside a Claude session", function()
    local r = run(dir .. "/src/a.lua:7", dir, nil)

    assert.equals(0, r.code)
    assert.equals("opened\n", r.stdout)
    assert.same({ { open = { dir .. "/src/a.lua", 7 } } }, calls)
  end)

  it("fails with the reason a jump gives for neither opening nor waiting", function()
    jump_answer = "not opened: you are editing"

    local r = run("src/a.lua", dir, "elsewhere")

    assert.equals(1, r.code)
    assert.truthy(r.stderr:find("not opened: you are editing", 1, true))
  end)

  it("refuses a file that isn't there, opening nothing", function()
    local r = run("src/gone.lua", dir, "s1")

    assert.equals(1, r.code)
    assert.truthy(r.stderr:find("no such file", 1, true))
    assert.same({}, calls)
  end)
end)
