-- The neo-tree build lua/plugins/explorer.lua pins must not accumulate libuv
-- handles across renders. v3.x (as of 2026-10) starts a fresh, self-rearming
-- resize-monitor timer chain on every render and never closes git process
-- handles; a 4.5h session reached ~340 concurrent chains (~600 timers/s, ~2GB
-- RSS). Exercises the plugin as installed by lazy, so it guards the pin rather
-- than our config. NEOTREE_PATH overrides the checkout, to test another build.

local assert = require("luassert")

local lazy = vim.fn.stdpath("data") .. "/lazy/"
local neotree = vim.env.NEOTREE_PATH or (lazy .. "neo-tree.nvim")
for _, dir in ipairs({ lazy .. "nui.nvim", lazy .. "plenary.nvim", neotree }) do
  vim.opt.runtimepath:prepend(dir)
end

--- Live libuv handles by type, counting only those not already closing.
---@return table<string, integer>
local function handles()
  local counts = {}
  vim.uv.walk(function(h)
    if not h:is_closing() then
      counts[h:get_type()] = (counts[h:get_type()] or 0) + 1
    end
  end)
  return counts
end

describe("neo-tree handle hygiene", function()
  -- Set up and open the tree once: re-running setup() per test would tear the
  -- tree down and muddy the handle counts.
  require("neo-tree").setup({
    log_to_file = false,
    enable_git_status = true,
    filesystem = { use_libuv_file_watcher = false },
  })
  require("neo-tree.command").execute({
    action = "show",
    source = "filesystem",
    dir = vim.fn.expand("~/.config/nvim"),
  })
  assert.is_true(
    vim.wait(3000, function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "neo-tree" then
          return true
        end
      end
      return false
    end),
    "neo-tree window never opened"
  )

  it("keeps one resize monitor across many renders", function()
    local manager = require("neo-tree.sources.manager")
    -- Let the first render (and its git status job) settle.
    vim.wait(1500)
    local before = handles().timer or 0
    for _ = 1, 20 do
      manager.refresh("filesystem")
      vim.wait(100)
    end
    vim.wait(1500)
    local after = handles().timer or 0
    -- One chain re-arms one timer; the leak adds one chain per render (~20).
    assert.is_true(after - before < 5, ("timers grew %d -> %d"):format(before, after))
  end)

  it("closes git process handles once they exit", function()
    vim.wait(1500)
    local before = handles().process or 0
    for _ = 1, 10 do
      require("neo-tree.sources.manager").refresh("filesystem")
      vim.wait(150)
    end
    -- Give every git status job time to exit and run its exit callback.
    vim.wait(3000)
    local after = handles().process or 0
    assert.are.equal(before, after, ("process handles %d -> %d"):format(before, after))
  end)
end)
