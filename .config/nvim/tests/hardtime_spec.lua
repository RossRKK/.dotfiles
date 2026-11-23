-- plugins/hardtime.lua on the real hardtime: insert-mode arrows move through an
-- open completion menu (agentic's prompt completes with the builtin one), and
-- stay disabled everywhere else.

local assert = require("luassert")

require("tests.helpers.plugins").add("hardtime.nvim")

local spec = require("plugins.hardtime")[1]
spec.config(spec, spec.opts)
-- hardtime's setup() enables itself from a timer.
assert(vim.wait(5000, function()
  return require("hardtime").is_plugin_enabled
end))

--- The buffer's lines after typing `keys` from normal mode at line 1.
---@param keys string
---@return string[]
local function typed(keys)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.api.nvim_feedkeys(vim.keycode(keys), "tx", false)
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

describe("hardtime's arrow keys in insert mode", function()
  before_each(function()
    vim.cmd("enew!")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "", "apple", "apricot" })
  end)

  after_each(function()
    vim.cmd("bwipeout!")
  end)

  it("<Down> picks the next item in a completion menu", function()
    assert.equals("apricot", typed("iap<C-n><Down><C-y><Esc>")[1])
  end)

  it("<Up> picks the previous item in a completion menu", function()
    assert.equals("apple", typed("iap<C-n><C-n><Up><C-y><Esc>")[1])
  end)

  it("<Down> stays disabled without a menu", function()
    assert.same({ "x", "apple", "apricot" }, typed("i<Down>x<Esc>"))
  end)

  it("<Up> stays disabled without a menu", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    vim.api.nvim_feedkeys(vim.keycode("i<Up>x<Esc>"), "tx", false)
    assert.same({ "one", "xtwo" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)

  it("still reaches a menu after hardtime is toggled off and on", function()
    require("hardtime").toggle()
    require("hardtime").toggle()
    assert.equals("apricot", typed("iap<C-n><Down><C-y><Esc>")[1])
    assert.same({ "x", "apple", "apricot" }, typed("ddO<Esc>i<Down>x<Esc>"))
  end)
end)
