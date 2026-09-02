-- util/edgy_pin.lua: user resizes of edgy panels become edgy's per-window
-- override. edgy itself is faked: its window cache, edgebar list, and animation
-- state.

local assert = require("luassert")

describe("edgy_pin", function()
  local pin, cache, equalized, anim

  local function fake_edgy_window(win, vertical, target)
    local edgebar = { vertical = vertical }
    cache[win] = { win = win, view = { edgebar = edgebar }, width = target, height = target }
    return cache[win]
  end

  before_each(function()
    vim.cmd("silent only!")
    cache = {}
    equalized = {}
    anim = {}
    package.loaded["edgy.window"] = { cache = cache }
    package.loaded["edgy.animate"] = { state = anim }
    package.loaded["edgy.layout"] = {
      foreach = function(positions, fn)
        for _, pos in ipairs(positions) do
          fn({
            equalize = function()
              equalized[#equalized + 1] = pos
            end,
          }, pos)
        end
      end,
    }
    package.loaded["util.edgy_pin"] = nil
    pin = require("util.edgy_pin")
  end)

  after_each(function()
    package.loaded["edgy.window"] = nil
    package.loaded["edgy.layout"] = nil
    package.loaded["edgy.animate"] = nil
  end)

  local function open_left(width)
    vim.cmd("topleft vsplit")
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_width(win, width)
    return win
  end

  it("ignores windows edgy does not manage", function()
    local win = open_left(20)
    assert.same({}, pin.pin({ win }))
    assert.is_nil(vim.w[win].edgy_width)
  end)

  it("skips a window that is already at edgy's target size", function()
    local win = open_left(20)
    fake_edgy_window(win, true, 20)
    assert.same({}, pin.pin({ win }))
    assert.is_nil(vim.w[win].edgy_width)
  end)

  it("pins the width of a side-bar window the user resized", function()
    local win = open_left(20)
    fake_edgy_window(win, true, 35)
    assert.same({ win }, pin.pin({ win }))
    assert.equal(20, vim.w[win].edgy_width)
    assert.is_nil(vim.w[win].edgy_height)
  end)

  it("pins the height of a bottom-bar window", function()
    vim.cmd("botright split")
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_height(win, 6)
    fake_edgy_window(win, false, 10)
    pin.pin({ win })
    assert.equal(6, vim.w[win].edgy_height)
    assert.is_nil(vim.w[win].edgy_width)
  end)

  it("never pins edgy's collapsed parking size", function()
    local win = open_left(1)
    fake_edgy_window(win, true, 35)
    assert.same({}, pin.pin({ win }))
  end)

  it("skips a frame of edgy's animation", function()
    local win = open_left(20)
    local ewin = fake_edgy_window(win, true, 35)
    anim[ewin] = { width = 20.4, height = 0 } -- edgy sets the window to round(20.4)
    assert.same({}, pin.pin({ win }))
    assert.is_nil(vim.w[win].edgy_width)
  end)

  it("pins an outside resize that lands mid-animation", function()
    local win = open_left(50)
    local ewin = fake_edgy_window(win, true, 35)
    anim[ewin] = { width = 30, height = 0 } -- animating 30 -> 35; window is at 50
    assert.same({ win }, pin.pin({ win }))
    assert.equal(50, vim.w[win].edgy_width)
    assert.equal(50, anim[ewin].width, "animated value snaps to the pinned size")
  end)

  it("reset equalizes every edgebar", function()
    pin.reset()
    assert.same({ "left", "right", "bottom", "top" }, equalized)
  end)
end)
