-- plugins/edgy.lua: the views' sizing that depends on other plugins' windows.

local assert = require("luassert")

--- The edgy view for fishmonger's background-task list.
local function tasks_view()
  for _, view in ipairs(require("plugins.edgy")[1].opts.right) do
    if view.ft == "fishmonger-tasks" then
      return view
    end
  end
end

describe("edgy's task-list view", function()
  before_each(function()
    vim.cmd("silent only!")
    vim.w.fishmonger_tasks_height = nil -- `only` keeps the window a spec marked
  end)

  it("takes the height fishmonger asks for, so edgy never undoes its resize", function()
    vim.cmd("split")
    vim.w.fishmonger_tasks_height = 3

    assert.equals(3, tasks_view().size.height())
  end)

  it("is a single row before fishmonger has asked for any", function()
    assert.equals(1, tasks_view().size.height())
  end)
end)
