-- The docked tree follows the disk without a manual `R`: files made outside nvim
-- (an agent in a terminal, a checkout) show up, in background tabs too. Runs the
-- real plugins/explorer.lua config() against the installed neo-tree, so it guards
-- our options, not neo-tree's defaults.

local assert = require("luassert")

local lazy = vim.fn.stdpath("data") .. "/lazy/"
for _, dir in ipairs({
  lazy .. "nui.nvim",
  lazy .. "plenary.nvim",
  lazy .. "nvim-web-devicons",
  lazy .. "neo-tree.nvim",
}) do
  vim.opt.runtimepath:prepend(dir)
end
vim.cmd("runtime! plugin/neo-tree.lua") -- defines :Neotree, which sidebar.open uses

require("plugins.explorer")[1].config()
local manager = require("neo-tree.sources.manager")
local sidebar = require("util.sidebar")

local root = vim.fs.normalize(vim.fn.resolve(vim.fn.tempname()))

--- A fresh directory under the temp root, with one file so the tree has a row.
---@param name string
---@return string
local function project(name)
  local dir = root .. "/" .. name
  vim.fn.mkdir(dir, "p")
  vim.fn.writefile({}, dir .. "/existing.txt")
  return dir
end

--- Whether the current tab's tree has drawn a row for `path`.
---@param path string
local function shows(path)
  local state = manager.get_state("filesystem")
  return state.tree ~= nil
    and pcall(state.tree.get_node, state.tree, path)
    and state.tree:get_node(path) ~= nil
end

--- Open a tab rooted at `dir` with its tree drawn, the way a workspace tab is.
---@param dir string
---@param prepare? fun(state: table) adjusts the tab's tree state before it first draws
---@return integer tab
local function open_workspace(dir, prepare)
  vim.cmd("tabnew")
  vim.cmd("tcd " .. vim.fn.fnameescape(dir))
  if prepare then
    prepare(manager.get_state("filesystem"))
  end
  sidebar.open()
  assert.is_true(
    vim.wait(3000, function()
      return shows(dir .. "/existing.txt")
    end),
    "tree never drew " .. dir
  )
  return vim.api.nvim_get_current_tabpage()
end

describe("the docked tree", function()
  it("shows a file created outside nvim", function()
    local dir = project("watched")
    open_workspace(dir)
    vim.fn.writefile({}, dir .. "/from_outside.txt") -- writefile() raises no BufWritePost
    assert.is_true(
      vim.wait(3000, function()
        return shows(dir .. "/from_outside.txt")
      end),
      "tree never showed the new file"
    )
  end)

  -- neo-tree refreshes only the current tab's tree and merely marks the rest dirty.
  it("shows a file created while its tab was in the background", function()
    local dir = project("background")
    local tab = open_workspace(dir)
    vim.cmd("tabnew")
    vim.fn.writefile({}, dir .. "/while_away.txt")
    assert.is_true(
      vim.wait(3000, function()
        return manager.get_state("filesystem", tab).dirty
      end),
      "the watcher never asked for a refresh"
    )
    vim.api.nvim_set_current_tabpage(tab)
    assert.is_true(
      vim.wait(3000, function()
        return shows(dir .. "/while_away.txt")
      end),
      "tree never showed the file on returning"
    )
  end)

  -- A refresh whose render lands after its tab was left is dropped, and neo-tree
  -- clears dirty before rendering, so the tree looks current but isn't.
  it("shows a file whose refresh finished in another tab", function()
    local dir = project("dropped")
    -- Test-only: no watcher, so nothing but the refreshes below reads the
    -- disk; synchronous scans, so the dropped render happens inside the
    -- navigate and dirty going false marks it done.
    local tab = open_workspace(dir, function(state)
      state.use_libuv_file_watcher = false
      state.async_directory_scan = "never"
    end)
    local state = manager.get_state("filesystem", tab)
    sidebar.refresh() -- opens neo-tree's 100ms navigate debounce, if the open hasn't already
    vim.fn.writefile({}, dir .. "/late.txt")
    sidebar.refresh() -- debounced: runs once the window ends, after the tab switch
    vim.cmd("tabnew")
    sidebar.refresh() -- marks the background tree dirty
    assert.is_true(state.dirty)
    assert.is_true(
      vim.wait(3000, function()
        return not state.dirty
      end),
      "the debounced refresh never ran"
    )
    vim.api.nvim_set_current_tabpage(tab)
    assert.is_true(
      vim.wait(3000, function()
        return shows(dir .. "/late.txt")
      end),
      "tree never showed the file on returning"
    )
  end)
end)
