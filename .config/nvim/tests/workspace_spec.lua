-- config.workspace: the explore picker and workspace numbering.

local assert = require("luassert")

describe("workspace.set_labels", function()
  --- The tab label with one terminal showing `icon`, as it shows on screen.
  local function label_with(icon)
    local real = package.loaded["fishmonger"]
    package.loaded["fishmonger"] = {
      tabs = function(_)
        return { { slot = 1, icon = icon, hl = "Comment" } }
      end,
    }
    local ok, err = pcall(require("config.workspace").set_labels)
    package.loaded["fishmonger"] = real
    assert(ok, err)
    return (vim.t.name:gsub("%%#[^#]*#", ""))
  end

  it("draws a label with a wide status glyph as wide as one with a narrow glyph", function()
    local narrow, wide = label_with("✓"), label_with("⏳")
    assert.truthy(wide:find("⏳", 1, true))
    assert.equals(vim.fn.strdisplaywidth(narrow), vim.fn.strdisplaywidth(wide))
  end)
end)

-- Full labels take 54 + 22 = 76 columns in the tab strip, two thirds of 114; without the repo, 45 + 10 = 55.
describe("workspace.set_labels fitting the screen", function()
  local ws, root, saved, columns, terms

  --- Number the current tabpage as workspace `slot` on a checkout `report` describes.
  local function checkout(dir, report)
    vim.fn.mkdir(dir, "p")
    vim.cmd.tcd(vim.fn.fnameescape(dir))
    ws.assign_slot()
    require("util.branch_reports")[vim.fs.normalize(dir)] = report
  end

  --- Run a Claude that goes by `name` as pid `pid` in terminal `slot` of tabpage `tab`.
  local function claude(tab, slot, pid, name)
    vim.fn.mkdir(root .. "/sessions", "p")
    vim.fn.writefile(
      { vim.json.encode({ pid = pid, name = name }) },
      root .. "/sessions/" .. pid .. ".json"
    )
    terms[tab] = { { slot = slot, agent = { agent_pid = pid, state = "done" } } }
    package.loaded["fishmonger"] = {
      tabs = function(t)
        return terms[t] or {}
      end,
    }
  end

  --- Every tab's label, left to right, after relabelling at `width` columns.
  local function labels_at(width)
    vim.o.columns = width
    ws.set_labels()
    return vim.tbl_map(function(tab)
      return vim.api.nvim_tabpage_get_var(tab, "name")
    end, vim.api.nvim_list_tabpages())
  end

  before_each(function()
    pcall(vim.cmd, "tabonly")
    vim.t.workspace_slot = nil
    saved = { fishmonger = package.loaded["fishmonger"] }
    package.loaded["fishmonger"] = nil
    package.loaded["config.workspace"] = nil
    ws = require("config.workspace")
    columns = vim.o.columns
    root = vim.fn.tempname()
    terms = {}
    ws.setup({
      agent_worktrees = true,
      claude_sessions = root .. "/sessions",
      claude_roles = root .. "/claude-roles",
    })
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
  end)

  after_each(function()
    vim.o.columns = columns
    ws.setup({ agent_worktrees = false })
    package.loaded["fishmonger"] = saved.fishmonger
    pcall(vim.cmd, "tabonly")
    vim.fn.delete(root, "rf")
  end)

  it("keeps the repo on every tab when they all fit in two thirds of the screen", function()
    assert.same(
      { "1 widget · helpful-teal · rkk/feature-cache-test-2", "2 .dotfiles - main" },
      labels_at(114)
    )
  end)

  it("drops the repo from every tab when they don't, and keeps the rest", function()
    assert.same({ "1 helpful-teal · rkk/feature-cache-test-2", "2 main" }, labels_at(113))
  end)

  it("drops the repo before the labels fill the screen, leaving the buffers room", function()
    assert.same({ "1 helpful-teal · rkk/feature-cache-test-2", "2 main" }, labels_at(76))
  end)

  it("drops nothing more when they still don't fit without the repo", function()
    assert.same({ "1 helpful-teal · rkk/feature-cache-test-2", "2 main" }, labels_at(30))
  end)

  it("names a checkout's agent after the Claude session in its terminal 1", function()
    claude(vim.api.nvim_list_tabpages()[2], 1, 4242, "dotty")
    assert.same({
      "1 widget · helpful-teal · rkk/feature-cache-test-2",
      "2 .dotfiles · dotty · main",
    }, labels_at(200))
  end)

  it("names a checkout after its standing role alone, the repo and branch left out", function()
    vim.fn.writefile({ root .. "/.dotfiles dotty" }, root .. "/claude-roles")
    claude(vim.api.nvim_list_tabpages()[2], 1, 4246, "dotty")
    assert.same(
      { "1 widget · helpful-teal · rkk/feature-cache-test-2", "2 dotty" },
      labels_at(200)
    )
  end)

  it("keeps the repo and branch once a role's session goes by another name", function()
    vim.fn.writefile({ root .. "/.dotfiles dotty" }, root .. "/claude-roles")
    claude(vim.api.nvim_list_tabpages()[2], 1, 4247, "calm-otter")
    assert.same({
      "1 widget · helpful-teal · rkk/feature-cache-test-2",
      "2 .dotfiles · calm-otter · main",
    }, labels_at(200))
  end)

  it("names a worktree's agent after its session once that has a name of its own", function()
    claude(vim.api.nvim_list_tabpages()[1], 1, 4243, "calm-otter")
    assert.same(
      { "1 widget · calm-otter · rkk/feature-cache-test-2", "2 .dotfiles - main" },
      labels_at(200)
    )
  end)

  it("names no agent after a Claude in another terminal", function()
    claude(vim.api.nvim_list_tabpages()[2], 2, 4244, "keen-heron")
    assert.same(
      { "1 widget · helpful-teal · rkk/feature-cache-test-2", "2 .dotfiles - main" },
      labels_at(200)
    )
  end)

  it("drops the repo and keeps the session's name when the labels don't fit", function()
    claude(vim.api.nvim_list_tabpages()[2], 1, 4245, "dotty")
    assert.same({ "1 helpful-teal · rkk/feature-cache-test-2", "2 dotty · main" }, labels_at(30))
  end)

  it("gives the repo back once the screen widens again", function()
    labels_at(30)
    assert.same(
      { "1 widget · helpful-teal · rkk/feature-cache-test-2", "2 .dotfiles - main" },
      labels_at(200)
    )
  end)
end)

-- util.worktree builds on config.workspace, so the prefix's worktree keys come in from the keymap.
describe("workspace.prefix", function()
  local real_getcharstr, keys

  before_each(function()
    real_getcharstr = vim.fn.getcharstr
    vim.fn.getcharstr = function(_, _)
      return table.remove(keys, 1)
    end
    package.loaded["util.worktree"] = nil
    package.preload["util.worktree"] = function()
      error("config.workspace required util.worktree")
    end
    package.loaded["config.workspace"] = nil
  end)

  after_each(function()
    vim.fn.getcharstr = real_getcharstr
    package.preload["util.worktree"] = nil
    package.loaded["config.workspace"] = nil
  end)

  it("runs the key it is given, without reaching for util.worktree", function()
    local ran = {}
    keys = { "w", "b" }
    local ws = require("config.workspace")
    for _ = 1, 2 do
      ws.prefix({
        w = function()
          ran[#ran + 1] = "w"
        end,
        b = function()
          ran[#ran + 1] = "b"
        end,
      })
    end
    assert.same({ "w", "b" }, ran)
  end)
end)

describe("workspace.agent_shell", function()
  it("continues this directory's last Claude conversation, else starts one, at a fish prompt, marked as terminal 1", function()
    assert.same(
      { "env", "WORKSPACE_TERMINAL=1", "fish", "-C", "claude --continue; or claude" },
      require("config.workspace").agent_shell(false)
    )
  end)

  it("tells that Claude the name to take when it has one", function()
    assert.same({
      "env",
      "WORKSPACE_TERMINAL=1",
      "CLAUDE_AGENT_NAME=keen-heron",
      "fish",
      "-C",
      "claude --continue; or claude",
    }, require("config.workspace").agent_shell(false, "keen-heron"))
  end)

  it("resumes the session it is given instead of continuing the directory's last", function()
    assert.same({
      "env",
      "WORKSPACE_TERMINAL=1",
      "fish",
      "-C",
      "claude --resume 5acea7d5-42e4-48ab-bae8-c06adaa57027",
    }, require("config.workspace").agent_shell(
      false,
      nil,
      "5acea7d5-42e4-48ab-bae8-c06adaa57027"
    ))
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
      tabs = function(_)
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
      tabs = function(_)
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
      sidebar = package.loaded["util.sidebar"],
      fishmonger = package.loaded["fishmonger"],
    }
    _G.Snacks = { dashboard = { update = function() end } }
    package.loaded["util.sidebar"] = { open = function() end }
    package.loaded["fishmonger"] = { show = function(_, _) end }
    package.loaded["config.workspace"] = nil
    ws = require("config.workspace")
    ws.set_labels = function() end -- the tab label reads fishmonger and bufferline
    ws.assign_slot()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
  end)

  after_each(function()
    pcall(vim.cmd, "tabonly")
    vim.fn.delete(dir, "rf")
    _G.Snacks = saved.snacks
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

  it("holds terminal 1 back until the directory is ready, then starts it in that tab", function()
    local origin = vim.api.nvim_get_current_tabpage()
    local ready, shown_in
    package.loaded["util.sidebar"].refresh = function() end
    package.loaded["fishmonger"].show = function(_, opts)
      shown_in = opts.tab
    end
    ws.open(dir, {
      tab = true,
      background = true,
      until_ready = function(cb)
        ready = cb
      end,
    })
    assert.is_true(vim.wait(1000, function()
      return ready ~= nil
    end))
    assert.is_nil(shown_in)

    ready()
    assert.equals(ws.find(dir), shown_in)
    assert.equals(origin, vim.api.nvim_get_current_tabpage())
  end)

  --- The windows WorkspaceReady hands over while `run` goes.
  local function ready_windows(run)
    local wins = {}
    local id = vim.api.nvim_create_autocmd("User", {
      pattern = "WorkspaceReady",
      callback = function(ev)
        wins[#wins + 1] = ev.data.win
      end,
    })
    run()
    vim.api.nvim_del_autocmd(id)
    return wins
  end

  it("hands the new tab's editor window over as soon as it is built", function()
    local wins = ready_windows(function()
      ws.open(dir, { tab = true })
    end)
    assert.same({ vim.api.nvim_tabpage_get_win(ws.find(dir)) }, wins)
  end)

  it("hands the editor window over only once the directory is ready", function()
    package.loaded["util.sidebar"].refresh = function() end
    local ready
    local before = ready_windows(function()
      ws.open(dir, {
        tab = true,
        until_ready = function(cb)
          ready = cb
        end,
      })
      assert.is_true(vim.wait(1000, function()
        return ready ~= nil
      end))
    end)
    assert.same({}, before)
    assert.same({ vim.api.nvim_tabpage_get_win(ws.find(dir)) }, ready_windows(ready))
  end)

  it("starts terminal 1's Claude under the agent name its directory gives", function()
    local shell
    package.loaded["fishmonger"].show = function(_, opts)
      shell = opts.shell
    end
    ws.agent_name = function(d)
      return d == dir and "keen-heron" or nil
    end
    ws.open(dir, { tab = true })
    assert.is_true(vim.wait(1000, function()
      return shell ~= nil
    end))
    assert.truthy(vim.tbl_contains(shell, "CLAUDE_AGENT_NAME=keen-heron"))
  end)

  it("does not switch to a tab already open on the directory", function()
    open({ tab = true })
    vim.cmd("tabprevious")
    local origin = vim.api.nvim_get_current_tabpage()
    ws.open(dir, { tab = true, background = true })
    assert.equals(origin, vim.api.nvim_get_current_tabpage())
  end)
end)

describe("workspace.display_name", function()
  local ws, dir

  local function report(git_dir, common_dir, branch)
    require("util.branch_reports")[vim.fs.normalize(dir)] = {
      repo = "dotfiles",
      branch = branch,
      git_dir = git_dir,
      common_dir = common_dir,
    }
  end

  before_each(function()
    ws = require("config.workspace")
    dir = vim.fn.tempname() .. "/.worktrees/keen-heron"
    vim.fn.mkdir(dir, "p")
    vim.cmd("tabnew")
    vim.cmd.tcd(vim.fn.fnameescape(dir))
  end)

  after_each(function()
    require("util.branch_reports")[vim.fs.normalize(dir)] = nil
    ws.setup({ agent_worktrees = false })
    pcall(vim.cmd, "tabonly")
    vim.fn.delete(vim.fs.dirname(vim.fs.dirname(dir)), "rf")
  end)

  it("names a worktree after its repo and branch", function()
    report("/r/.git/worktrees/keen-heron", "/r/.git", "rkk/x")
    assert.equals("dotfiles - rkk/x", ws.display_name())
  end)

  it("with agent worktrees, names a worktree after its repo, its agent and the branch it has out", function()
    ws.setup({ agent_worktrees = true })
    report("/r/.git/worktrees/keen-heron", "/r/.git", "rkk/x")
    assert.equals("dotfiles · keen-heron · rkk/x", ws.display_name())
    report("/r/.git/worktrees/keen-heron", "/r/.git", "rkk/y")
    assert.equals("dotfiles · keen-heron · rkk/y", ws.display_name())
  end)

  it("with agent worktrees, names a worktree with nothing out after its repo and agent", function()
    ws.setup({ agent_worktrees = true })
    report("/r/.git/worktrees/keen-heron", "/r/.git", nil)
    assert.equals("dotfiles · keen-heron", ws.display_name())
  end)

  it("with agent worktrees, still names the main checkout after the repo", function()
    ws.setup({ agent_worktrees = true })
    report("/r/.git", "/r/.git", "main")
    assert.equals("dotfiles - main", ws.display_name())
  end)
end)

-- M.agent_name against a real repo and one of its linked worktrees.
describe("workspace.agent_name", function()
  local ws, dir, repo

  local function git(...)
    local cmd = { "git", "-c", "user.name=t", "-c", "user.email=t@t", ... }
    local res = vim.system(cmd, { cwd = repo, text = true }):wait()
    assert(res.code == 0, table.concat(cmd, " ") .. ": " .. (res.stderr or ""))
  end

  before_each(function()
    ws = require("config.workspace")
    dir = vim.fn.tempname()
    repo = dir .. "/repo"
    vim.fn.mkdir(repo, "p")
    git("init", "-q", "-b", "main")
    git("commit", "-q", "--allow-empty", "-m", "init")
    git("worktree", "add", "-q", repo .. "/.worktrees/keen-heron")
    vim.fn.mkdir(repo .. "/.worktrees/keen-heron/sub", "p")
    ws.setup({ agent_worktrees = true })
  end)

  after_each(function()
    ws.setup({ agent_worktrees = false })
    vim.fn.delete(dir, "rf")
  end)

  it("names a linked worktree's agent after its directory, from anywhere in it", function()
    assert.equals("keen-heron", ws.agent_name(repo .. "/.worktrees/keen-heron"))
    assert.equals("keen-heron", ws.agent_name(repo .. "/.worktrees/keen-heron/sub"))
  end)

  it("leaves the main checkout's agent to its own name", function()
    assert.is_nil(ws.agent_name(repo))
  end)

  it("leaves a directory outside git to its own name", function()
    assert.is_nil(ws.agent_name(dir))
  end)

  it("with agent worktrees off, names no agent", function()
    ws.setup({ agent_worktrees = false })
    assert.is_nil(ws.agent_name(repo .. "/.worktrees/keen-heron"))
  end)
end)
