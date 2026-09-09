-- The pure half of util/bufferline_diag.lua: severity counts in, bufferline's
-- per-buffer diagnostics table out.

local assert = require("luassert")
local bd = require("util.bufferline_diag")
local S = vim.diagnostic.severity

describe("bufferline_diag.build", function()
  it("sums the counts and names the worst severity", function()
    local got = bd.build({ [3] = { [S.ERROR] = 1, [S.WARN] = 2, [S.HINT] = 4 } })
    assert.same({ [3] = { count = 7, level = "error", errors = { error = 1, warning = 2, hint = 4 } } }, got)
  end)

  it("picks warning when there is no error", function()
    assert.equals("warning", bd.build({ [1] = { [S.WARN] = 1, [S.INFO] = 9 } })[1].level)
  end)

  it("leaves out buffers with nothing to show", function()
    assert.same({}, bd.build({ [1] = {}, [2] = { [S.ERROR] = 0 } }))
  end)
end)

describe("bufferline_diag.collect", function()
  it("only asks about loaded buffers", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local ns = vim.api.nvim_create_namespace("bufferline_diag_spec")
    vim.diagnostic.set(ns, buf, { { lnum = 0, col = 0, message = "x", severity = S.ERROR } })
    assert.same({ [S.ERROR] = 1 }, bd.collect()[buf])
    vim.api.nvim_buf_delete(buf, { force = true })
    assert.is_nil(bd.collect()[buf])
  end)
end)
