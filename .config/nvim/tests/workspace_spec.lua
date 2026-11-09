-- config.workspace: the explore picker and workspace numbering.

local assert = require("luassert")

describe("workspace.agent_shell", function()
  it("continues this directory's last Claude conversation at a fish prompt, marked as terminal 1", function()
    assert.same(
      { "env", "WORKSPACE_TERMINAL=1", "fish", "-C", "claude --continue" },
      require("config.workspace").agent_shell(false)
    )
  end)
end)

-- <M-b>e: a browser for a project that is NOT open yet, so it must start at
-- ~ rather than following the current buffer's file (the explorer default).
describe("workspace.explore", function()
  local saved_snacks, got

  before_each(function()
    saved_snacks = _G.Snacks
    got = nil
    _G.Snacks = { picker = { explorer = function(opts)
      got = opts
    end } }
  end)

  after_each(function()
    _G.Snacks = saved_snacks
  end)

  it("starts at ~ and does not follow the current file", function()
    require("config.workspace").explore()
    assert.equals(vim.env.HOME, got.cwd)
    assert.is_false(got.follow_file)
  end)
end)

describe("workspace numbers", function()
  local ws

  --- Open a tabpage and number it as a workspace, as workspace.open does.
  local function open_ws()
    vim.cmd("tabnew")
    ws.assign_slot()
    return vim.api.nvim_get_current_tabpage()
  end

  --- The tab strip, left to right, as workspace numbers (nil -> "-").
  local function strip()
    local out = {}
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      out[#out + 1] = ws.slot(tab) or "-"
    end
    return out
  end

  before_each(function()
    pcall(vim.cmd, "tabonly")
    vim.t.workspace_slot = nil
    package.loaded["config.workspace"] = nil
    ws = require("config.workspace")
    ws.assign_slot() -- the startup tabpage is workspace 1
  end)

  it("numbers workspaces in order of opening", function()
    open_ws()
    open_ws()
    assert.same({ 1, 2, 3 }, strip())
  end)

  it("keeps the others' numbers when one closes, leaving a gap", function()
    local two = open_ws()
    local three = open_ws()
    vim.cmd(vim.api.nvim_tabpage_get_number(two) .. "tabclose")
    assert.same({ 1, 3 }, strip())
    assert.equals(three, ws.tab(3))
    assert.is_nil(ws.tab(2))
  end)

  it("fills the gap and moves into number order", function()
    local two = open_ws()
    open_ws()
    vim.cmd(vim.api.nvim_tabpage_get_number(two) .. "tabclose")
    -- Opened from the last tabpage, so tabnew lands after workspace 3.
    vim.api.nvim_set_current_tabpage(ws.tab(3))
    local new = open_ws()
    assert.equals(new, ws.tab(2))
    assert.same({ 1, 2, 3 }, strip())
  end)

  it("moves to the front when it takes number 1", function()
    local one = vim.api.nvim_get_current_tabpage()
    open_ws()
    vim.cmd(vim.api.nvim_tabpage_get_number(one) .. "tabclose")
    open_ws()
    assert.same({ 1, 2 }, strip())
  end)

  it("keeps an existing number when the tabpage is opened over again", function()
    local two = open_ws()
    ws.assign_slot()
    assert.equals(2, ws.slot(two))
    assert.same({ 1, 2 }, strip())
  end)

  it("does not number a tabpage that is not a workspace", function()
    vim.cmd("tabnew") -- the dap debug tab, say
    assert.is_nil(ws.slot())
    open_ws()
    assert.same({ 1, "-", 2 }, strip())
  end)

  it("switches by number", function()
    local two = open_ws()
    vim.api.nvim_set_current_tabpage(ws.tab(1))
    ws.switch(2)
    assert.equals(two, vim.api.nvim_get_current_tabpage())
  end)

  it("offers the project picker for a number not in use, to open it as that number", function()
    local here = vim.api.nvim_get_current_tabpage()
    local asked
    ws.pick_new = function(opts)
      asked = opts
    end
    ws.switch(5)
    assert.same({ tab = true, slot = 5 }, asked)
    assert.equals(here, vim.api.nvim_get_current_tabpage())
  end)

  it("takes the number asked for when it is free, in order", function()
    vim.cmd("tabnew")
    ws.assign_slot(5)
    open_ws()
    assert.same({ 1, 2, 5 }, strip())
  end)

  it("renumbers into a free number and keeps the strip in order", function()
    local one = vim.api.nvim_get_current_tabpage()
    open_ws()
    vim.api.nvim_set_current_tabpage(one)
    ws.renumber(4)
    assert.same({ 2, 4 }, strip())
    assert.equals(one, ws.tab(4))
    assert.equals(one, vim.api.nvim_get_current_tabpage())
  end)

  it("swaps numbers when renumbering onto a taken one", function()
    local one = vim.api.nvim_get_current_tabpage()
    local two = open_ws()
    local three = open_ws()
    vim.api.nvim_set_current_tabpage(three)
    ws.renumber(1)
    assert.equals(three, ws.tab(1))
    assert.equals(one, ws.tab(3))
    assert.equals(two, ws.tab(2))
    assert.same({ 1, 2, 3 }, strip())
    assert.equals(three, vim.api.nvim_get_current_tabpage())
  end)

  it("puts the new number on the label", function()
    open_ws()
    ws.renumber(7)
    assert.matches("^7 ", vim.t.name)
  end)

  it("reads <M-b> . N as renumber and <M-b> N as switch", function()
    require("config.keymaps")
    local one = vim.api.nvim_get_current_tabpage()
    open_ws()
    local keys = function(k)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(k, true, false, true), "x", false)
    end
    keys("<M-b>.5")
    assert.same({ 1, 5 }, strip())
    keys("<M-b>1")
    assert.equals(one, vim.api.nvim_get_current_tabpage())
  end)

  it("opens the worktree picker on <M-b> w, a new branch on <M-b> b and the browser on <M-b> e without waiting for a number", function()
    require("config.keymaps")
    local picked, branched, explored = 0, 0, 0
    package.loaded["util.worktree"] = {
      pick = function()
        picked = picked + 1
      end,
      new = function()
        branched = branched + 1
      end,
    }
    ws.explore = function()
      explored = explored + 1
    end
    local keys = function(k)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(k, true, false, true), "x", false)
    end
    keys("<M-b>w")
    keys("<M-b>b")
    keys("<M-b>e")
    package.loaded["util.worktree"] = nil
    assert.equals(1, picked)
    assert.equals(1, branched)
    assert.equals(1, explored)
  end)

  it("closes a workspace without asking when no agent is live", function()
    package.loaded["fishmonger"] = {
      tabs = function()
        return { { slot = 1 }, { slot = 2, agent = { state = "done" } } }
      end,
    }
    local asked = false
    local confirm = vim.fn.confirm
    vim.fn.confirm = function(msg, choices, default) ---@diagnostic disable-line: duplicate-set-field, unused-local
      asked = true
      return 2
    end
    open_ws()
    ws.close()
    vim.fn.confirm = confirm
    package.loaded["fishmonger"] = nil
    assert.is_false(asked)
    assert.same({ 1 }, strip())
  end)

  it("asks before closing a workspace with a live agent, and cancel keeps it", function()
    package.loaded["fishmonger"] = {
      tabs = function()
        return { { slot = 1, agent = { state = "permission" } } }
      end,
    }
    local asked
    local confirm = vim.fn.confirm
    vim.fn.confirm = function(msg, choices, default) ---@diagnostic disable-line: duplicate-set-field, unused-local
      asked = msg
      return 2 -- Cancel
    end
    open_ws()
    ws.close()
    vim.fn.confirm = confirm
    package.loaded["fishmonger"] = nil
    assert.matches("1 agent is still working", asked)
    assert.same({ 1, 2 }, strip())
  end)

  it("falls back to the lowest free number when the one asked for is taken", function()
    vim.cmd("tabnew")
    ws.assign_slot(1)
    assert.same({ 1, 2 }, strip())
  end)
end)

describe("workspace.open on a directory already open", function()
  local ws, root

  --- A workspace tabpage on `dir`, set up the way open() leaves one.
  local function open_ws(dir)
    vim.cmd("tabnew")
    vim.cmd.tcd(vim.fn.fnameescape(dir))
    ws.assign_slot()
    return vim.api.nvim_get_current_tabpage()
  end

  before_each(function()
    pcall(vim.cmd, "tabonly")
    vim.t.workspace_slot = nil
    package.loaded["config.workspace"] = nil
    ws = require("config.workspace")
    ws.assign_slot()
    root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/wt/sub", "p")
    root = vim.uv.fs_realpath(root)
  end)

  after_each(function()
    pcall(vim.cmd, "tabonly")
    vim.fn.delete(root, "rf")
  end)

  it("switches to the existing tab instead of opening a second", function()
    local wt = open_ws(root .. "/wt")
    open_ws(root)
    local count = #vim.api.nvim_list_tabpages()
    ws.open(root .. "/wt/", { tab = true })
    assert.equals(wt, vim.api.nvim_get_current_tabpage())
    assert.equals(count, #vim.api.nvim_list_tabpages())
  end)

  it("matches through a symlink", function()
    local wt = open_ws(root .. "/wt")
    vim.uv.fs_symlink(root .. "/wt", root .. "/link")
    assert.equals(wt, ws.find(root .. "/link"))
  end)

  it("treats a subdirectory as a workspace of its own", function()
    open_ws(root .. "/wt")
    assert.is_nil(ws.find(root .. "/wt/sub"))
  end)

  it("ignores a tabpage that is not a workspace", function()
    vim.cmd("tabnew") -- the dap debug tab, say
    vim.cmd.tcd(vim.fn.fnameescape(root .. "/wt"))
    assert.is_nil(ws.find(root .. "/wt"))
  end)
end)

-- A tab an agent opens (worktree-tab) is built, then hands focus back.
describe("workspace.open in the background", function()
  local ws, dir, saved

  before_each(function()
    pcall(vim.cmd, "tabonly")
    vim.t.workspace_slot = nil
    saved = {
      snacks = _G.Snacks,
      greeter = package.loaded["config.greeter"],
      sidebar = package.loaded["util.sidebar"],
      fishmonger = package.loaded["fishmonger"],
    }
    _G.Snacks = { dashboard = { update = function() end } }
    package.loaded["config.greeter"] = { open = function() end }
    package.loaded["util.sidebar"] = { open = function() end }
    package.loaded["fishmonger"] = { show = function(_, _) end }
    package.loaded["config.workspace"] = nil
    ws = require("config.workspace")
    ws.set_label = function() end -- the tab label reads fishmonger and bufferline
    ws.assign_slot()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
  end)

  after_each(function()
    pcall(vim.cmd, "tabonly")
    vim.fn.delete(dir, "rf")
    _G.Snacks = saved.snacks
    package.loaded["config.greeter"] = saved.greeter
    package.loaded["util.sidebar"] = saved.sidebar
    package.loaded["fishmonger"] = saved.fishmonger
  end)

  --- Opens `dir` with `opts` and waits for open()'s deferred half to finish.
  local function open(opts)
    local tabs = #vim.api.nvim_list_tabpages()
    local built = false
    package.loaded["fishmonger"].show = function()
      vim.schedule(function()
        built = true
      end)
    end
    ws.open(dir, opts)
    assert.is_true(vim.wait(1000, function()
      return built
    end))
    assert.equals(tabs + 1, #vim.api.nvim_list_tabpages())
  end

  it("builds the new tab, then returns to the tab you were on", function()
    local origin = vim.api.nvim_get_current_tabpage()
    open({ tab = true, background = true })
    assert.equals(origin, vim.api.nvim_get_current_tabpage())
    assert.is_not_nil(ws.find(dir))
  end)

  it("without background, leaves you on the new tab", function()
    open({ tab = true })
    assert.equals(ws.find(dir), vim.api.nvim_get_current_tabpage())
  end)

  it("does not switch to a tab already open on the directory", function()
    open({ tab = true })
    vim.cmd("tabprevious")
    local origin = vim.api.nvim_get_current_tabpage()
    ws.open(dir, { tab = true, background = true })
    assert.equals(origin, vim.api.nvim_get_current_tabpage())
  end)
end)
