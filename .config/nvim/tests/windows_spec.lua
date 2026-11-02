local assert = require("luassert")
local windows = require("config.windows")

-- A terminal buffer with no process behind it: buftype=terminal is all the
-- routing looks at.
local function terminal_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_open_term(buf, {})
  return buf
end

local function file_buf(name)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, name)
  return buf
end

describe("main window routing", function()
  local explorer, main, side

  before_each(function()
    vim.cmd("silent! only!")
    -- explorer | main | side panel, as a workspace lays it out.
    explorer = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(explorer, vim.api.nvim_create_buf(false, true))
    main = vim.api.nvim_open_win(file_buf(vim.fn.tempname()), false, { split = "right", win = explorer })
    side = vim.api.nvim_open_win(terminal_buf(), false, { split = "right", win = main })
    vim.w[side].fishmonger_side = true
  end)

  it("prefers a file window over a terminal in the main area", function()
    vim.api.nvim_open_win(terminal_buf(), false, { split = "below", win = main })
    assert.equals(main, windows.main_window())
  end)

  it("falls back to a main-area terminal, never the side panel", function()
    vim.api.nvim_win_set_buf(main, terminal_buf())
    assert.equals(main, windows.main_window())
  end)

  it("ignores a floating terminal", function()
    vim.api.nvim_win_close(main, true)
    vim.api.nvim_open_win(terminal_buf(), false, { relative = "editor", row = 1, col = 1, width = 10, height = 5 })
    assert.is_nil(windows.main_window())
  end)

  it("opens a file over the main-area terminal, which lives on hidden", function()
    local term = terminal_buf()
    vim.api.nvim_win_set_buf(main, term)
    vim.api.nvim_set_current_win(side)

    windows.goto_main_window()
    vim.cmd.edit(vim.fn.fnameescape(vim.fn.tempname()))

    assert.equals(main, vim.api.nvim_get_current_win())
    assert.equals("", vim.bo[vim.api.nvim_win_get_buf(main)].buftype)
    assert.is_true(vim.api.nvim_buf_is_valid(term))
  end)
end)
