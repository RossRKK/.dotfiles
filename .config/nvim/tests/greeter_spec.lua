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
