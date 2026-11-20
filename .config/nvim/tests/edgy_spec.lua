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

-- A tab can host a chat buffer, so the panel is docked whichever kind of tab it shows.
for _, ft in ipairs({ "fishmonger", "codecompanion" }) do
  describe("edgy's side panel view for " .. ft, function()
    it("docks the window fishmonger marks as its panel, not the editor beside it", function()
      vim.cmd("silent only!")
      vim.w.fishmonger_side = nil
      local editor = vim.api.nvim_get_current_win()
      vim.cmd("vsplit")
      local panel = vim.api.nvim_get_current_win()
      vim.w[panel].fishmonger_side = true

      assert.is_true(view(ft).filter(nil, panel))
      assert.falsy(view(ft).filter(nil, editor))
    end)
  end)
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
