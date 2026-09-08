local assert = require("luassert")

-- Deletes must behave as stock Vim: no mapping on d/c/x, and a delete lands in
-- the unnamed register and the numbered history. A black hole mapping once
-- swallowed these so a delete could never be pasted back; this pins its absence.
describe("delete registers", function()
  before_each(function()
    require("config.keymaps")
    vim.cmd("enew!")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "first", "second", "third" })
    vim.fn.setreg('"', "")
    vim.fn.setreg("1", "")
    vim.fn.setreg("-", "")
  end)

  after_each(function()
    vim.cmd("bwipeout!")
  end)

  it("leaves d, c and x unmapped", function()
    for _, key in ipairs({ "d", "D", "c", "C", "x", "X" }) do
      assert.equals("", vim.fn.maparg(key, "n"), key .. " is mapped in normal mode")
      assert.equals("", vim.fn.maparg(key, "x"), key .. " is mapped in visual mode")
    end
  end)

  it("puts a linewise delete in the unnamed register and register 1", function()
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    vim.cmd("normal dd")
    assert.equals("second\n", vim.fn.getreg('"'))
    assert.equals("second\n", vim.fn.getreg("1"))
  end)

  it("puts a small delete in the minus register", function()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal x")
    assert.equals("f", vim.fn.getreg('"'))
    assert.equals("f", vim.fn.getreg("-"))
  end)
end)
