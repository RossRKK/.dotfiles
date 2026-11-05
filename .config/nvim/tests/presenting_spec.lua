local assert = require("luassert")
local presenting = require("util.presenting")

local function fake_hardtime()
  local ht = { is_plugin_enabled = true }
  function ht.enable()
    ht.is_plugin_enabled = true
  end
  function ht.disable()
    ht.is_plugin_enabled = false
  end
  return ht
end

describe("presenting", function()
  after_each(function()
    vim.o.mouse = ""
  end)

  it("turns hardtime off and the mouse on", function()
    local ht = fake_hardtime()
    presenting.set(ht, true)
    assert.is_false(ht.is_plugin_enabled)
    assert.equals("a", vim.o.mouse)
    assert.is_true(presenting.is_on(ht))
  end)

  it("goes back to hardtime on and keyboard only", function()
    local ht = fake_hardtime()
    presenting.set(ht, true)
    presenting.set(ht, false)
    assert.is_true(ht.is_plugin_enabled)
    assert.equals("", vim.o.mouse)
    assert.is_false(presenting.is_on(ht))
  end)
end)
