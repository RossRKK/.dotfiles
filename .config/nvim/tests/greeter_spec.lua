-- Layout decisions in config/greeter.lua that would otherwise show up as a
-- crowded or crooked greeter. Snacks and jj are not run here: the sections are
-- inspected as data, and the jj log cache is seeded by hand.

local assert = require("luassert")
local greeter = require("config.greeter")
local jjlog = require("util.jjlog")

local function width_of(item)
  local total = 0
  for _, chunk in ipairs(item.text) do
    total = total + vim.fn.strdisplaywidth(chunk[1])
  end
  return total
end

describe("greeter.sections", function()
  it("starts with a blank line so Agents never touches the top edge", function()
    local sections = greeter.sections("/nowhere", 0, 0, function()
      return nil
    end)
    assert.same({ padding = 1 }, sections[1])
  end)
end)

describe("greeter.graph", function()
  local root = "/tmp/greeter_spec_repo"
  local buf

  before_each(function()
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    jjlog.cache[root] = ("@  " .. ("x"):rep(200)) .. "\n" .. "│  short\n"
  end)

  after_each(function()
    jjlog.cache[root] = nil
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  it("is wider than snacks' 60-column default", function()
    assert.is_true(greeter.PANE_WIDTH > 60)
  end)

  it("cuts a long line to the pane width", function()
    vim.o.columns = 200
    local items = greeter.graph(root, buf)
    assert.equals(greeter.PANE_WIDTH, width_of(items[1]))
    assert.equals("│  short", items[2].text[1][1])
  end)

  it("cuts to the window instead when that is narrower", function()
    vim.o.columns = 40
    local items = greeter.graph(root, buf)
    assert.equals(vim.api.nvim_win_get_width(0), width_of(items[1]))
  end)
end)

-- Regression: a snacks dashboard's update() puts the cursor on an action item in
-- the window it opened in, without checking what that window shows now. Our
-- greeters stay alive after a file is opened over them, so refreshing a hidden
-- one used to yank the file's cursor (seen on every save that moved vcsline).
describe("greeter.update_dashboards", function()
  local dash_buf, dash, updates

  -- A fresh, named-by-content buffer each time: `:enew` on an empty unnamed
  -- buffer reuses it, which would make the "file" and the dashboard one buffer.
  local function show_new_buffer(lines)
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_win_set_buf(0, buf)
    return buf
  end

  before_each(function()
    dash_buf = show_new_buffer({ "greeter" })
    updates = 0
    -- Stand-in for the object Snacks.dashboard.open() returns: remembers its
    -- window and, like snacks, moves that window's cursor when updated.
    dash = { win = vim.api.nvim_get_current_win() }
    function dash.update(self)
      updates = updates + 1
      vim.api.nvim_win_set_cursor(self.win, { 1, 0 })
    end
    greeter._instances[dash_buf] = dash
  end)

  after_each(function()
    greeter._instances[dash_buf] = nil
    vim.cmd("%bwipeout!")
  end)

  it("updates a dashboard that is shown in its own window", function()
    greeter.update_dashboards()
    assert.equals(1, updates)
  end)

  it("leaves the cursor alone once a file is opened over the dashboard", function()
    show_new_buffer({ "one", "two", "three" })
    vim.api.nvim_win_set_cursor(0, { 3, 2 })

    greeter.update_dashboards()

    assert.equals(0, updates)
    assert.same({ 3, 2 }, vim.api.nvim_win_get_cursor(0))
  end)

  it("forgets a dashboard whose buffer is gone", function()
    show_new_buffer({ "other" })
    vim.api.nvim_buf_delete(dash_buf, { force = true })
    greeter.update_dashboards()
    assert.is_nil(greeter._instances[dash_buf])
  end)
end)
