-- Window geometry in config/ide.lua: the side terminal's width and the 80-column
-- floor that protects it on narrow screens.

local assert = require("luassert")
local ide = require("config.ide")

describe("ide.term_width", function()
  local columns, tree_width

  before_each(function()
    columns = vim.o.columns
    tree_width = ide.tree_width
    -- No explorer window exists headlessly; fake its width per-test instead.
    ide.tree_width = function()
      return 0
    end
  end)

  after_each(function()
    vim.o.columns = columns
    ide.tree_width = tree_width
  end)

  it("takes 40% of the screen when no explorer is open", function()
    vim.o.columns = 300
    assert.equals(120, ide.term_width())
  end)

  it("measures the 40% against the region left of the explorer", function()
    vim.o.columns = 300
    ide.tree_width = function()
      return 100
    end
    assert.equals(80, ide.term_width()) -- (300 - 100) * 0.4
  end)

  it("floors at 80 columns when 40% would be narrower", function()
    vim.o.columns = 100
    assert.equals(80, ide.term_width()) -- 40% is 40; the floor wins
  end)

  -- The floor is absolute: a screen too small to honour it still yields 80, and
  -- nvim clamps the resulting split rather than letting the terminal shrink.
  it("holds the 80 floor even when the screen is narrower than it", function()
    vim.o.columns = 40
    assert.equals(80, ide.term_width())
  end)

  it("rounds down rather than up", function()
    vim.o.columns = 251
    assert.equals(100, ide.term_width()) -- 251 * 0.4 = 100.4
  end)
end)

describe("ide.tree_width", function()
  it("is 0 when no explorer window exists", function()
    assert.equals(0, ide.tree_width())
  end)

  -- +1 for the window separator column the tree costs the rest of the layout.
  it("includes the separator column of a live explorer window", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "NvimTree"
    vim.cmd("vsplit")
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_win_set_width(win, 30)

    assert.equals(31, ide.tree_width())

    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)

describe("ide.is_ide_mode", function()
  -- Captured once at module load from argv, so headless (no directory argument)
  -- is always text-editor mode. Pins the contract the terminal/explorer autocmds
  -- branch on.
  it("is false when nvim was not given a single directory", function()
    assert.is_false(ide.is_ide_mode())
  end)
end)
