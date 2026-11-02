-- util.sidebar.reveal (<leader>v): the docked tree never leaves the workspace,
-- and a file outside it (a crate under ~/.cargo) is shown in a float instead.
-- Drives the installed neo-tree, so it guards the dir= behaviour reveal leans on.

local assert = require("luassert")

local lazy = vim.fn.stdpath("data") .. "/lazy/"
for _, dir in ipairs({ lazy .. "nui.nvim", lazy .. "plenary.nvim", lazy .. "neo-tree.nvim" }) do
  vim.opt.runtimepath:prepend(dir)
end

local sidebar = require("util.sidebar")

--- Create `path` (and its parents) as an empty file, returning it.
local function touch(path)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile({}, path)
  return path
end

local root = vim.fs.normalize(vim.fn.resolve(vim.fn.tempname()))
local workspace = root .. "/project"
local crate = root .. "/registry/tokio-1.40.0"
local inside = touch(workspace .. "/src/main.rs")
local crate_file = touch(crate .. "/src/runtime/mod.rs")
touch(crate .. "/Cargo.toml")
local loose = touch(root .. "/loose/notes.txt")

describe("sidebar.reveal_target", function()
  it("keeps files in the workspace in the tree", function()
    assert.same({ kind = "tree" }, sidebar.reveal_target(inside, workspace))
  end)

  it("keeps a buffer with no file in the tree", function()
    assert.same({ kind = "tree" }, sidebar.reveal_target(nil, workspace))
  end)

  it("floats a file outside the workspace at its project root", function()
    assert.same({ kind = "float", root = crate }, sidebar.reveal_target(crate_file, workspace))
  end)

  it("floats a file with no project at its own directory", function()
    -- Under the temp dir, so no marker above it either.
    assert.same({ kind = "float", root = root .. "/loose" }, sidebar.reveal_target(loose, workspace))
  end)

  it("treats a sibling sharing the workspace's prefix as outside", function()
    local sibling = touch(root .. "/project-old/a.rs")
    assert.equals("float", sidebar.reveal_target(sibling, workspace).kind)
  end)
end)

describe("sidebar.reveal", function()
  local manager, saved_snacks, floated

  --- The filesystem tree's root, once neo-tree has opened it.
  local function tree_root()
    local state
    vim.wait(3000, function()
      state = manager.get_state("filesystem")
      return state.path ~= nil and sidebar.win("filesystem") ~= nil
    end)
    return state.path
  end

  require("neo-tree").setup({
    log_to_file = false,
    enable_git_status = false,
    filesystem = { bind_to_cwd = false, use_libuv_file_watcher = false },
  })
  manager = require("neo-tree.sources.manager")
  vim.cmd("tcd " .. vim.fn.fnameescape(workspace))

  before_each(function()
    sidebar.close() -- reveal focuses the tree; each case edits from the editor
    saved_snacks = _G.Snacks
    floated = nil
    _G.Snacks = { picker = { explorer = function(opts)
      floated = opts
    end } }
  end)

  after_each(function()
    _G.Snacks = saved_snacks
  end)

  it("reveals a workspace file without moving the tree or the tab cwd", function()
    vim.cmd("edit " .. vim.fn.fnameescape(inside))
    sidebar.reveal()
    assert.equals(workspace, tree_root())
    assert.equals(workspace, vim.fn.getcwd(-1, 0))
    assert.is_nil(floated)
  end)

  it("floats a crate file and leaves the tree and the tab cwd alone", function()
    vim.cmd("edit " .. vim.fn.fnameescape(crate_file))
    sidebar.reveal()
    assert.equals(crate, floated.cwd)
    assert.equals(workspace, tree_root())
    assert.equals(workspace, vim.fn.getcwd(-1, 0))
  end)

  it("puts a tree that was navigated away back on the workspace", function()
    require("neo-tree.command").execute({ action = "show", source = "filesystem", dir = crate })
    vim.wait(3000, function()
      return manager.get_state("filesystem").path == crate
    end)
    vim.cmd("edit " .. vim.fn.fnameescape(inside))
    sidebar.reveal()
    vim.wait(3000, function()
      return manager.get_state("filesystem").path == workspace
    end)
    assert.equals(workspace, tree_root())
  end)
end)
