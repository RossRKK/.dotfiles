-- config.workspace's naming: the jj side of display_name. vcsline and
-- jjworkspace are stubbed so no repo is needed; the git side reads the
-- greeter's report and is exercised through greeter_spec.

local assert = require("luassert")

describe("workspace.jj_name", function()
  local ws, info

  before_each(function()
    info = nil
    package.loaded["util.vcsline"] = {
      root_of = function(dir)
        return dir:match("^(.*/ionics/%.worktrees/[^/]+)") or dir:match("^(.*/ionics)")
      end,
      info_for = function()
        return info
      end,
      format = function(i, short)
        return short and i.bookmark or (i.bookmark .. " " .. i.change_id)
      end,
    }
    package.loaded["util.jjworkspace"] = {
      root = function()
        return "/home/me/dev/ionics"
      end,
    }
    package.loaded["config.workspace"] = nil
    ws = require("config.workspace")
  end)

  after_each(function()
    package.loaded["util.vcsline"] = nil
    package.loaded["util.jjworkspace"] = nil
    package.loaded["config.workspace"] = nil
  end)

  it("is the repo and the short statusline fragment", function()
    info = { bookmark = "main+1", change_id = "unlqxzkz" }
    assert.equals("ionics - main+1", ws.jj_name("/home/me/dev/ionics/src"))
  end)

  it("names a secondary workspace after the main repo, not its directory", function()
    info = { bookmark = "dd-x+2", change_id = "mxnuyzlm" }
    assert.equals("ionics - dd-x+2", ws.jj_name("/home/me/dev/ionics/.worktrees/dd-x"))
  end)

  it("is the bare repo before vcsline has answered", function()
    assert.equals("ionics", ws.jj_name("/home/me/dev/ionics"))
  end)

  it("is nil outside a jj repo", function()
    assert.is_nil(ws.jj_name("/home/me/other"))
  end)
end)

describe("workspace.greeter_name", function()
  local ws, info

  before_each(function()
    info = nil
    package.loaded["util.vcsline"] = {
      root_of = function(dir)
        return dir:match("^(.*/ionics)")
      end,
      info_for = function()
        return info
      end,
    }
    package.loaded["util.jjworkspace"] = {
      root = function()
        return "/home/me/dev/ionics"
      end,
    }
    package.loaded["config.workspace"] = nil
    ws = require("config.workspace")
    ws.cwd = function()
      return "/home/me/dev/ionics"
    end
  end)

  after_each(function()
    package.loaded["util.vcsline"] = nil
    package.loaded["util.jjworkspace"] = nil
    package.loaded["config.workspace"] = nil
  end)

  it("is the repo and the jj workspace name", function()
    info = { bookmark = "main", change_id = "unlqxzkz", workspace = "default" }
    assert.equals("ionics - default", ws.greeter_name())
  end)

  it("is the bare repo before vcsline has answered", function()
    assert.equals("ionics", ws.greeter_name())
  end)
end)

-- <leader>te: a browser for a project that is NOT open yet, so it must start at
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

  it("aims <M-b> w N at the worktree picker and <M-b> e N at the browser", function()
    require("config.keymaps")
    local picked, explored
    package.loaded["util.vcs"] = {
      pick_tab = function(slot)
        picked = slot
      end,
    }
    ws.explore = function(opts)
      explored = opts
    end
    local keys = function(k)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(k, true, false, true), "x", false)
    end
    keys("<M-b>w4")
    keys("<M-b>e6")
    keys("<M-b>wx") -- not a number: nothing
    package.loaded["util.vcs"] = nil
    assert.equals(4, picked)
    assert.same({ tab = true, slot = 6 }, explored)
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
