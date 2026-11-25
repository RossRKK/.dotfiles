-- The shared quickfix list (config/quickfix.lua): set and docked under the main window, its visited entries
-- remembered, and ]q stepping in the main window from anywhere.

local assert = require("luassert")
local quickfix = require("config.quickfix")

---@param lines string[]
---@return string path
local function file_with(lines)
  local path = vim.fn.tempname() .. ".txt"
  vim.fn.writefile(lines, path)
  return path
end

local function quickfix_windows()
  return vim.tbl_filter(function(win)
    return vim.fn.getwininfo(win)[1].quickfix == 1
  end, vim.api.nvim_tabpage_list_wins(0))
end

describe("config.quickfix", function()
  local main, path

  before_each(function()
    vim.cmd("silent! cclose | silent! only! | enew!")
    vim.fn.setqflist({}, "f")
    quickfix.setup()
    path = file_with({ "one", "two", "three", "four" })
    vim.cmd.edit(path)
    main = vim.api.nvim_get_current_win()
  end)

  after_each(function()
    vim.api.nvim_del_augroup_by_name("quickfix")
  end)

  ---@return integer the list's id
  local function two_stops()
    return quickfix.set("Walk", {
      { path = path, line = 2, text = "the second line" },
      { path = path, line = 4, text = "the fourth line" },
    })
  end

  it(
    "makes the entries the current list, docked under the main window without taking focus",
    function()
      two_stops()

      local list = vim.fn.getqflist({ title = 0, items = 0 })
      assert.equals("Walk", list.title)
      assert.same(
        { 2, 4 },
        vim.tbl_map(function(item)
          return item.lnum
        end, list.items)
      )
      local docked = quickfix_windows()
      assert.equals(1, #docked)
      assert.equals(vim.fn.win_screenpos(main)[2], vim.fn.win_screenpos(docked[1])[2])
      assert.is_true(vim.fn.win_screenpos(docked[1])[1] > vim.fn.win_screenpos(main)[1])
      assert.equals(main, vim.api.nvim_get_current_win())
    end
  )

  it("sizes the window to the list, up to five rows, again for each new list", function()
    two_stops()
    local docked = quickfix_windows()[1]
    assert.equals(2, vim.api.nvim_win_get_height(docked))

    local many = {}
    for line = 1, 4 do
      table.insert(many, { path = path, line = line, text = "a" })
      table.insert(many, { path = path, line = line, text = "b" })
    end
    quickfix.set("Many", many)

    assert.equals(5, vim.api.nvim_win_get_height(docked))
  end)

  it("reuses an open quickfix window for the next list", function()
    two_stops()
    two_stops()

    assert.equals(1, #quickfix_windows())
  end)

  it("has no state for an empty list", function()
    assert.is_nil(quickfix.state())
  end)

  it("states the list, the current entry and the entries the cursor has been on", function()
    local id = two_stops()
    vim.api.nvim_win_set_cursor(main, { 4, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = vim.api.nvim_get_current_buf() })

    local state = quickfix.state()

    assert.equals(id, state.id)
    assert.equals("Walk", state.title)
    assert.equals(1, state.current)
    assert.same({ 2 }, state.visited)
    assert.same(
      { path = vim.fn.fnamemodify(path, ":~:."), line = 2, text = "the second line" },
      state.entries[1]
    )
  end)

  it("does not count a line without an entry as visited", function()
    two_stops()
    vim.api.nvim_win_set_cursor(main, { 3, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = vim.api.nvim_get_current_buf() })

    assert.same({}, quickfix.state().visited)
  end)

  it("follows an entry whose line moved after an edit above it", function()
    two_stops()
    vim.api.nvim_buf_set_lines(0, 0, 0, false, { "inserted" })
    vim.api.nvim_win_set_cursor(main, { 3, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = vim.api.nvim_get_current_buf() })

    assert.same({ 1 }, quickfix.state().visited)
  end)

  it("steps to the next entry in the main window from a window that is not an editor", function()
    two_stops()
    local chat = vim.api.nvim_create_buf(false, true)
    vim.cmd("vsplit")
    vim.api.nvim_win_set_buf(0, chat)
    local chat_win = vim.api.nvim_get_current_win()

    vim.cmd("normal ]q")

    assert.equals(chat, vim.api.nvim_win_get_buf(chat_win))
    assert.equals(main, vim.api.nvim_get_current_win())
    assert.equals(2, vim.fn.getqflist({ idx = 0 }).idx)
  end)

  it(
    "opens the entry under the cursor in the greeter's window, not the window used last",
    function()
      local greeter = vim.api.nvim_create_buf(true, true)
      require("config.windows").mark_placeholder(greeter)
      vim.api.nvim_win_set_buf(main, greeter)
      two_stops()
      local chat = vim.api.nvim_create_buf(false, true)
      vim.cmd("vsplit")
      vim.api.nvim_win_set_buf(0, chat)
      local chat_win = vim.api.nvim_get_current_win()
      local docked = quickfix_windows()[1]
      vim.api.nvim_set_current_win(docked)
      vim.api.nvim_win_set_cursor(docked, { 2, 0 })

      vim.cmd("normal \r")

      assert.equals(chat, vim.api.nvim_win_get_buf(chat_win))
      assert.equals(main, vim.api.nvim_get_current_win())
      assert.equals(2, vim.fn.getqflist({ idx = 0 }).idx)
      assert.equals(4, vim.api.nvim_win_get_cursor(main)[1])
    end
  )

  it("goes to the last entry on ]Q without a count", function()
    quickfix.set("Three", {
      { path = path, line = 1, text = "a" },
      { path = path, line = 2, text = "b" },
      { path = path, line = 3, text = "c" },
    })

    vim.cmd("normal ]Q")

    assert.equals(3, vim.fn.getqflist({ idx = 0 }).idx)
  end)
end)
