-- The todo split (config/todo.lua): closed when a file takes over the main
-- window, and only then.

local assert = require("luassert")
local todo = require("config.todo")

local todo_file = vim.fs.normalize(vim.fn.tempname() .. "-todo.md")

local function file_buf()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, vim.fn.tempname())
  return buf
end

-- Run everything vim.schedule has queued so far (callbacks run in order).
local function flush()
  local done = false
  vim.schedule(function()
    done = true
  end)
  vim.wait(1000, function()
    return done
  end)
end

describe("todo split closing", function()
  local main, todo_win

  before_each(function()
    vim.cmd("silent! only!")
    todo.setup(todo_file)
    main = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(main, file_buf())
    flush()
    todo_win = todo.open_below(main, todo_file)
    flush()
  end)

  after_each(function()
    vim.api.nvim_del_augroup_by_name("todo_split")
  end)

  it("survives its own opening", function()
    assert.equals(todo_win, todo.window(0, todo_file))
  end)

  it("closes when a file opens in the main window", function()
    vim.api.nvim_win_set_buf(main, file_buf())
    flush()
    assert.is_nil(todo.window(0, todo_file))
  end)

  it("stays for a terminal in the main window", function()
    local term = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_open_term(term, {})
    vim.api.nvim_win_set_buf(main, term)
    flush()
    assert.equals(todo_win, todo.window(0, todo_file))
  end)

  it("stays for an unlisted buffer in the main window", function()
    local buf = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname())
    vim.api.nvim_win_set_buf(main, buf)
    flush()
    assert.equals(todo_win, todo.window(0, todo_file))
  end)

  it("stays for a file opened in a float", function()
    local float = vim.api.nvim_open_win(file_buf(), true, { relative = "editor", row = 1, col = 1, width = 20, height = 5 })
    flush()
    assert.equals(todo_win, todo.window(0, todo_file))
    vim.api.nvim_win_close(float, true)
  end)
end)
