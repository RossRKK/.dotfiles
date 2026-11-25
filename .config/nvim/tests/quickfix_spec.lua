-- Quickfix entries open in the main window (config/quickfix.lua): ]q and friends, and Enter in the list.

local assert = require("luassert")
local quickfix = require("config.quickfix")

---@param lines string[]
---@return string path
local function file_with(lines)
  local path = vim.fn.tempname() .. ".txt"
  vim.fn.writefile(lines, path)
  return path
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

  --- Make `lines` of the test file the current quickfix list.
  ---@param lines integer[]
  local function list_of(lines)
    vim.fn.setqflist({}, " ", {
      items = vim.tbl_map(function(lnum)
        return { filename = path, lnum = lnum, text = "line " .. lnum }
      end, lines),
    })
  end

  it("steps to the next entry in the main window from a window that is not an editor", function()
    list_of({ 2, 4 })
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
      list_of({ 2, 4 })
      vim.api.nvim_win_call(main, function()
        vim.cmd("belowright copen")
      end)
      local docked = vim.fn.getqflist({ winid = 0 }).winid
      local chat = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_win(main)
      vim.cmd("vsplit")
      vim.api.nvim_win_set_buf(0, chat)
      local chat_win = vim.api.nvim_get_current_win()
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
    list_of({ 1, 2, 3 })

    vim.cmd("normal ]Q")

    assert.equals(3, vim.fn.getqflist({ idx = 0 }).idx)
  end)
end)
