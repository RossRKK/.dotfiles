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

-- nvim's terminal must forward Shift+Enter to the child untouched, so a
-- kitty-protocol program (Claude Code) gets CSI 13;2u. An <Esc><CR> map once
-- sat here and made Claude submit instead of insert a newline.
describe("terminal Shift+Enter", function()
  it("leaves <S-CR> unmapped in terminal mode", function()
    require("config.keymaps")
    assert.equals("", vim.fn.maparg("<S-CR>", "t"))
  end)
end)

-- <leader>ya types the cursor's path:line (a visual selection's path:first-last)
-- into the side terminal via fishmonger.send, unsubmitted, for a comment to the
-- agent to follow.
describe("<leader>ya", function()
  local sent

  before_each(function()
    sent = {}
    package.loaded["fishmonger"] = {
      send = function(text)
        sent[#sent + 1] = text
        return true
      end,
    }
    require("config.keymaps")
    vim.cmd("enew!")
    vim.api.nvim_buf_set_name(0, vim.fn.getcwd() .. "/lua/sample.lua")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a", "b", "c", "d" })
  end)

  after_each(function()
    vim.cmd("bwipeout!")
    package.loaded["fishmonger"] = nil
  end)

  local function press(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "mx", false)
  end

  it("sends the cursor line as path:line with a trailing space", function()
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    press("<leader>ya")
    assert.same({ "lua/sample.lua:3 " }, sent)
  end)

  it("sends a visual selection as path:first-last, either direction", function()
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    press("Vk<leader>ya")
    assert.same({ "lua/sample.lua:2-3 " }, sent)
    assert.equals("n", vim.fn.mode())
  end)

  it("sends nothing from a buffer with no file", function()
    vim.cmd("enew!")
    press("<leader>ya")
    assert.same({}, sent)
  end)
end)

-- gf/gF are the builtins, routed to the main editor window: from a panel (the
-- terminal, here a nofile stand-in) the file opens in the main window and the
-- panel keeps its buffer.
describe("gf/gF", function()
  local target, previous, main, panel, panel_buf

  before_each(function()
    require("config.keymaps")
    vim.cmd("silent only!")
    target = vim.fn.tempname() .. ".txt"
    previous = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "one", "two", "three", "four" }, target)
    vim.fn.writefile({ "previous" }, previous)
    vim.cmd("edit " .. previous)
    main = vim.api.nvim_get_current_win()
    vim.cmd("vnew")
    panel = vim.api.nvim_get_current_win()
    panel_buf = vim.api.nvim_get_current_buf()
    vim.bo.buftype = "nofile"
  end)

  after_each(function()
    vim.cmd("silent only!")
    vim.cmd("silent! %bwipeout!")
    vim.fn.delete(target)
    vim.fn.delete(previous)
  end)

  local function press_on(keys, text)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { text })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.api.nvim_feedkeys(keys, "mx", false)
  end

  it("gF from a panel opens the file at the line in the main window", function()
    press_on("gF", target .. ":3")
    assert.equals(main, vim.api.nvim_get_current_win())
    assert.equals(target, vim.api.nvim_buf_get_name(0))
    assert.same({ 3, 0 }, vim.api.nvim_win_get_cursor(0))
    assert.equals(panel_buf, vim.api.nvim_win_get_buf(panel))
    assert.equals(2, #vim.api.nvim_tabpage_list_wins(0))
  end)

  it("gf from a panel opens the file in the main window, ignoring the line", function()
    press_on("gf", target .. ":3")
    assert.equals(main, vim.api.nvim_get_current_win())
    assert.equals(target, vim.api.nvim_buf_get_name(0))
    assert.same({ 1, 0 }, vim.api.nvim_win_get_cursor(0))
  end)

  it("keeps the main window's previous file as the alternate", function()
    press_on("gF", target .. ":3")
    assert.equals(previous, vim.fn.fnamemodify(vim.fn.bufname("#"), ":p"))
  end)

  it("changes nothing when the file doesn't exist", function()
    press_on("gF", "/nonexistent/file.txt:3")
    assert.equals(panel, vim.api.nvim_get_current_win())
    assert.equals(panel_buf, vim.api.nvim_win_get_buf(panel))
    assert.equals(previous, vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(main)))
    assert.equals(2, #vim.api.nvim_tabpage_list_wins(0))
  end)

  it("from the main window opens in place, as the builtin", function()
    vim.api.nvim_set_current_win(main)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { target .. ":3" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.api.nvim_feedkeys("gF", "mx", false)
    assert.equals(main, vim.api.nvim_get_current_win())
    assert.equals(target, vim.api.nvim_buf_get_name(0))
    assert.same({ 3, 0 }, vim.api.nvim_win_get_cursor(0))
  end)
end)
