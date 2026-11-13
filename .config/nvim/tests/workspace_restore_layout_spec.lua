-- A restored workspace tab is laid out like one opened by hand, tree included.
-- Drives the installed neo-tree, whose navigate debounce once dropped the trees of tabs opened together.

local assert = require("luassert")

local lazy = vim.fn.stdpath("data") .. "/lazy/"
for _, dir in ipairs({ lazy .. "nui.nvim", lazy .. "plenary.nvim", lazy .. "neo-tree.nvim" }) do
  vim.opt.runtimepath:prepend(dir)
end

-- util.sidebar opens the tree through :Neotree, which the plugin file defines.
vim.cmd("runtime plugin/neo-tree.lua")
require("neo-tree").setup({
  log_to_file = false,
  enable_git_status = false,
  filesystem = { bind_to_cwd = false, use_libuv_file_watcher = false },
})
require("util.sidebar").setup()

local root = vim.fs.normalize(vim.fn.resolve(vim.fn.tempname()))
local dirs = { root .. "/one", root .. "/two", root .. "/three" }
for _, dir in ipairs(dirs) do
  vim.fn.mkdir(dir, "p")
  vim.fn.writefile({}, dir .. "/file.txt")
end

--- A tabpage's window tree with each window shown as its buffer's filetype.
---@param tab integer
---@return string
local function shape(tab)
  local function walk(node)
    if node[1] == "leaf" then
      local ft = vim.bo[vim.api.nvim_win_get_buf(node[2])].filetype
      return ft == "" and "editor" or ft
    end
    return node[1] .. "[" .. table.concat(vim.tbl_map(walk, node[2]), ", ") .. "]"
  end
  return walk(vim.fn.winlayout(vim.api.nvim_tabpage_get_number(tab)))
end

describe("a restored workspace tab", function()
  local ws, state, saved, started

  --- Every workspace's layout by directory, once each tab's tree is up (or two seconds pass).
  ---@return table<string, string>
  local function layouts()
    vim.wait(2000, function()
      for _, dir in ipairs(dirs) do
        local tab = ws.find(dir)
        if not tab or not shape(tab):find("neo-tree", 1, true) then
          return false
        end
      end
      return true
    end)
    local by_dir = {}
    for _, dir in ipairs(dirs) do
      local tab = ws.find(dir)
      by_dir[dir] = tab and shape(tab) or "not open"
    end
    return by_dir
  end

  --- Waits for each open()'s deferred half, which starts terminal 1.
  ---@param count integer
  local function await_terminals(count)
    assert.is_true(vim.wait(2000, function()
      return started >= count
    end))
  end

  before_each(function()
    vim.cmd("tabnew")
    vim.cmd("tabonly")
    vim.cmd("cd " .. vim.fn.fnameescape(root))
    saved = { snacks = _G.Snacks, fishmonger = package.loaded["fishmonger"] }
    _G.Snacks = { dashboard = { update = function() end } }
    started = 0
    package.loaded["fishmonger"] = {
      show = function(_, _)
        started = started + 1
      end,
      tabs = function(_)
        return {}
      end,
    }
    package.loaded["config.workspace"] = nil
    package.loaded["util.workspace_state"] = nil
    ws = require("config.workspace")
    ws.set_labels = function() end -- the tab label reads fishmonger and bufferline
    state = require("util.workspace_state")
    local file = root .. "/workspaces.json"
    local saved_projects = {}
    for i, dir in ipairs(dirs) do
      saved_projects[dir] = { slot = i }
    end
    vim.fn.writefile({ vim.json.encode(saved_projects) }, file)
    state.setup({ file = file, claude_projects = root .. "/claude" })
  end)

  after_each(function()
    vim.cmd("tabnew")
    vim.cmd("tabonly")
    _G.Snacks = saved.snacks
    package.loaded["fishmonger"] = saved.fishmonger
  end)

  --- Each directory opened in its own tab by hand, one at a time.
  ---@return table<string, string>
  local function opened_by_hand()
    local by_dir = {}
    for i, dir in ipairs(dirs) do
      ws.open(dir, { tab = true })
      await_terminals(i)
      assert.is_true(vim.wait(2000, function()
        return shape(ws.find(dir)):find("neo-tree", 1, true) ~= nil
      end))
      by_dir[dir] = shape(ws.find(dir))
    end
    vim.cmd("tabnew")
    vim.cmd("tabonly")
    started = 0
    return by_dir
  end

  it("from :WorkspaceRestore matches one opened by hand", function()
    local want = opened_by_hand()
    vim.cmd("WorkspaceRestore")
    await_terminals(#dirs)
    assert.same(want, layouts())
  end)

  it("from the start screen, taking over its tab, matches one opened by hand", function()
    local want = opened_by_hand()
    state.restore({ drop_buf = vim.api.nvim_get_current_buf() })
    await_terminals(#dirs)
    assert.same(want, layouts())
  end)
end)
