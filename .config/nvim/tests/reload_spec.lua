-- util.reload: re-running edited config modules in place.

local assert = require("luassert")

local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/rt", "p")
local reload = require("util.reload")
reload.setup(root)

--- Write `mod`'s file and give it an mtime no earlier write in this test shares.
local stamp = os.time()
local function write(mod, lines)
  local path = root .. "/" .. mod:gsub("%.", "/") .. ".lua"
  vim.fn.writefile(lines, path)
  stamp = stamp + 10
  vim.uv.fs_utime(path, stamp, stamp)
end

local function module_v(version)
  return {
    "local M = {}",
    "local count = 0",
    "local function bump() count = count + 1 return count end",
    "function M.bump() return bump() end",
    "function M.version() return " .. version .. " end",
    "M.label = 'v" .. version .. "'",
    "return M",
  }
end

describe("util.reload", function()
  it("swaps in the edited functions on the table callers hold, keeping its state", function()
    write("rt.counter", module_v(1))
    local live = require("rt.counter")
    live.bump()
    live.bump()
    write("rt.counter", module_v(2))
    assert.same({ "rt.counter" }, reload.reload().reloaded)
    assert.equals(live, require("rt.counter"))
    assert.equals(2, live.version())
    assert.equals(3, live.bump())
    assert.equals("v1", live.label)
  end)

  it("leaves an unedited module alone", function()
    write("rt.quiet", { "vim.g.quiet_runs = (vim.g.quiet_runs or 0) + 1" })
    require("rt.quiet")
    reload.reload()
    assert.equals(1, vim.g.quiet_runs)
  end)

  it("drops a deleted keymap and does not double an autocmd", function()
    local both = {
      "vim.keymap.set('n', '<leader>zq', '<nop>')",
      "vim.keymap.set('n', '<leader>zr', '<nop>')",
      "vim.api.nvim_create_autocmd('User', { pattern = 'ReloadSpec', callback = function()",
      "  vim.g.fired = (vim.g.fired or 0) + 1",
      "end })",
    }
    write("rt.side", both)
    require("rt.side")
    write("rt.side", { both[2], both[3], both[4], both[5] })
    reload.reload()
    assert.equals("", vim.fn.maparg("<leader>zq", "n"))
    assert.not_equals("", vim.fn.maparg("<leader>zr", "n"))
    vim.api.nvim_exec_autocmds("User", { pattern = "ReloadSpec" })
    assert.equals(1, vim.g.fired)
  end)

  it("keeps the old module working when the edit doesn't parse", function()
    write("rt.broken", module_v(1))
    local live = require("rt.broken")
    write("rt.broken", { "local M = {" })
    local result = reload.reload()
    assert.same({}, result.reloaded)
    assert.is_string(result.failed["rt.broken"])
    assert.equals(1, live.version())
  end)
end)
