local assert = require("luassert")

describe("options", function()
  it("starts with the mouse off", function()
    vim.o.mouse = "a"
    package.loaded["config.options"] = nil
    require("config.options")
    assert.equals("", vim.o.mouse)
  end)
end)
