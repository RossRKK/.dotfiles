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

  it("opens a file from the side panel in the main window, at a line and column", function()
    local path = vim.fn.tempname()
    vim.fn.writefile({ "one", "two", "three" }, path)
    vim.api.nvim_set_current_win(side)

    windows.open(path, 2, 3)

    assert.equals(main, vim.api.nvim_get_current_win())
    assert.equals(path, vim.api.nvim_buf_get_name(0))
    assert.same({ 2, 2 }, vim.api.nvim_win_get_cursor(0))
  end)

  it("keeps a line past the end inside the file", function()
    local path = vim.fn.tempname()
    vim.fn.writefile({ "one", "two" }, path)

    windows.open(path, 99)

    assert.same({ 2, 0 }, vim.api.nvim_win_get_cursor(0))
  end)
end)

describe("a placeholder's held height", function()
  local main, companion

  before_each(function()
    vim.cmd("silent! only!")
    windows.setup()
    main = vim.api.nvim_get_current_win()
    local placeholder = vim.api.nvim_create_buf(true, true)
    windows.mark_placeholder(placeholder)
    vim.api.nvim_win_set_buf(main, placeholder)
    companion = vim.api.nvim_open_win(
      vim.api.nvim_create_buf(false, true),
      false,
      { split = "below", win = main }
    )
    windows.mark_companion(companion, main)
  end)

  after_each(function()
    vim.api.nvim_del_augroup_by_name("main_companions")
  end)

  it("holds its window at that height beside its companions", function()
    windows.hold_height(main, 2)
    assert.equals(2, vim.api.nvim_win_get_height(main))
    assert.is_true(vim.wo[main].winfixheight)
  end)

  it("lets go of the window once a file is shown in it", function()
    windows.hold_height(main, 2)
    vim.api.nvim_win_set_buf(main, file_buf(vim.fn.tempname()))
    assert.is_false(vim.api.nvim_win_is_valid(companion))
    assert.is_false(vim.wo[main].winfixheight)
  end)

  it("leaves a window with no companion under it at its height", function()
    vim.api.nvim_win_close(companion, true)
    local height = vim.api.nvim_win_get_height(main)
    windows.hold_height(main, 2)
    assert.equals(height, vim.api.nvim_win_get_height(main))
    assert.is_false(vim.wo[main].winfixheight)
  end)
end)
