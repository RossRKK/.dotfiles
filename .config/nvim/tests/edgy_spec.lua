-- plugins/edgy.lua: the views' sizing that depends on other plugins' windows.

local assert = require("luassert")

--- The edgy view for windows of filetype `ft`.
local function view(ft)
  for _, v in ipairs(require("plugins.edgy")[1].opts.right) do
    if v.ft == ft then
      return v
    end
  end
end

for _, list in ipairs({
  { ft = "fishmonger-tasks", var = "fishmonger_tasks_height" },
  { ft = "fishmonger-files", var = "fishmonger_files_height" },
}) do
  describe("edgy's " .. list.ft .. " view", function()
    before_each(function()
      vim.cmd("silent only!")
      vim.w[list.var] = nil -- `only` keeps the window a spec marked
    end)

    it("takes the height fishmonger asks for, so edgy never undoes its resize", function()
      vim.cmd("split")
      vim.w[list.var] = 3

      assert.equals(3, view(list.ft).size.height())
    end)

    it("is a single row before fishmonger has asked for any", function()
      assert.equals(1, view(list.ft).size.height())
    end)
  end)
end
