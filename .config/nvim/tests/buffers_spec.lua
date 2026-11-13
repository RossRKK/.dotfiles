-- plugins/buffers.lua on the real bufferline: the workspace tabs leave room for the current buffer.

local assert = require("luassert")

local lazy = vim.fn.stdpath("data") .. "/lazy/"
for _, dir in ipairs({ lazy .. "nvim-web-devicons", lazy .. "bufferline.nvim" }) do
  vim.opt.runtimepath:prepend(dir)
end

describe("the bufferline beside the workspace tabs", function()
  local ws, root, columns

  --- Number the current tabpage as a workspace on a checkout `report` describes.
  local function checkout(dir, report)
    vim.fn.mkdir(dir, "p")
    vim.cmd.tcd(vim.fn.fnameescape(dir))
    ws.assign_slot()
    require("util.branch_reports")[vim.fs.normalize(dir)] = report
  end

  --- The bufferline as drawn `width` columns wide.
  local function bar_at(width)
    vim.o.columns = width
    return vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true }).str
  end

  --- How many columns of the bar drawn `width` wide are left blank between the buffers and the tabs.
  local function slack_at(width)
    vim.o.columns = width
    local bar =
      vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true, highlights = true })
    local blank = 0
    for i, hl in ipairs(bar.highlights) do
      if hl.group == "BufferLineFill" then
        local stop = bar.highlights[i + 1] and bar.highlights[i + 1].start or #bar.str
        blank = blank + vim.api.nvim_strwidth(bar.str:sub(hl.start + 1, stop))
      end
    end
    return blank
  end

  --- Each tab's label on a drawn bar, left to right.
  local function labels(bar)
    local found = {}
    for label in bar:gmatch("▏ (.-) ▕") do
      found[#found + 1] = label
    end
    return found
  end

  before_each(function()
    columns = vim.o.columns
    pcall(vim.cmd, "tabonly")
    vim.t.workspace_slot = nil
    package.loaded["config.workspace"] = nil
    ws = require("config.workspace")
    root = vim.fn.tempname()
    ws.setup({
      agent_worktrees = true,
      claude_sessions = root .. "/sessions",
      claude_roles = root .. "/claude-roles",
    })
    require("bufferline").setup(require("plugins.buffers")[1].opts)
    checkout(root .. "/widget/.worktrees/helpful-teal", {
      repo = "widget",
      branch = "rkk/feature-cache-test-2",
      git_dir = "/r/.git/worktrees/helpful-teal",
      common_dir = "/r/.git",
    })
    vim.cmd("tabnew")
    checkout(
      root .. "/.dotfiles",
      { repo = ".dotfiles", branch = "main", git_dir = "/d/.git", common_dir = "/d/.git" }
    )
    vim.cmd.edit(vim.fn.fnameescape(root .. "/.dotfiles/alpha.lua"))
    ws.set_labels()
  end)

  after_each(function()
    vim.o.columns = columns
    ws.setup({ agent_worktrees = false })
    pcall(vim.cmd, "tabonly")
    vim.cmd("silent! %bwipeout!")
    vim.fn.delete(root, "rf")
  end)

  it("keeps the current buffer on the bar unless even the shortest labels leave no room", function()
    local shortest = { "1 helpful-teal", "2 .dotfiles" }
    -- From where the shortest labels fit (36 columns) on their own.
    for width = 36, 140 do
      local bar = bar_at(width)
      assert(
        bar:find("alpha.lua", 1, true) or vim.deep_equal(shortest, labels(bar)),
        ("at %d columns: %s"):format(width, bar)
      )
    end
  end)

  it(
    "shortens the labels a step at a time, only as the screen narrows past what they need",
    function()
      local steps = {
        { "1 widget · helpful-teal · rkk/feature-cache-test-2", "2 .dotfiles - main" },
        { "1 helpful-teal · rkk/feature-cache-test-2", "2 main" },
        { "1 helpful-teal", "2 .dotfiles" },
      }
      local step = 1
      for width = 140, 36, -1 do
        local drawn = labels(bar_at(width))
        while step < #steps and not vim.deep_equal(steps[step], drawn) do
          step = step + 1
        end
        assert.same(steps[step], drawn, ("at %d columns"):format(width))
      end
      assert.equals(#steps, step)
    end
  )

  it(
    "keeps the full labels at the narrowest screen they fit on beside the current buffer",
    function()
      local full = { "1 widget · helpful-teal · rkk/feature-cache-test-2", "2 .dotfiles - main" }
      local width = 140
      while vim.deep_equal(full, labels(bar_at(width - 1))) do
        width = width - 1
      end
      -- bufferline counts the separator after its last buffer tile, which it never draws.
      assert.equals(1, slack_at(width))
      assert.equals(2, slack_at(width + 1))
      assert.truthy(bar_at(width):find("alpha.lua", 1, true))
    end
  )
end)
