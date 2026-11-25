-- config.workspace: the explore picker and workspace numbering.

local assert = require("luassert")

--- Each tab's label in a tab strip, left to right, as it draws on screen.
---@param strip string
---@return string[]
local function drawn_labels(strip)
  local drawn = vim.api.nvim_eval_statusline(strip, { use_tabline = true, maxwidth = 1000 }).str
  local labels = {}
  for label in drawn:gmatch("▏ (.-) ▕") do
    labels[#labels + 1] = label
  end
  return labels
end

describe("workspace.tab_strip glyphs", function()
  --- The current tab's label with one terminal showing `icon`, as it shows on screen.
  local function label_with(icon)
    local real = package.loaded["fishmonger"]
    package.loaded["fishmonger"] = {
      tabs = function(_)
        return { { slot = 1, icon = icon, hl = "Comment" } }
      end,
    }
    vim.cmd("tabnew")
    local ws = require("config.workspace")
    local ok, err = pcall(ws.set_labels)
    local labels = drawn_labels(ws.tab_strip(1000))
    pcall(vim.cmd, "tabonly")
    package.loaded["fishmonger"] = real
    assert(ok, err)
    return labels[2]
  end

  it("draws a label with a wide status glyph as wide as one with a narrow glyph", function()
    local narrow, wide = label_with("✓"), label_with("⏳")
    assert.truthy(wide:find("⏳", 1, true))
    assert.equals(vim.fn.strdisplaywidth(narrow), vim.fn.strdisplaywidth(wide))
  end)

  it("draws nothing for a lone tabpage, as bufferline shows no tabs then", function()
    pcall(vim.cmd, "tabonly")
    require("config.workspace").set_labels()
    assert.equals("", require("config.workspace").tab_strip(1000))
  end)
end)

-- Full labels take 54 + 22 = 76 columns in the tab strip, 79 with the close button; without the repo,
-- 58; without the branch too, 36.
describe("workspace.tab_strip fitting its room", function()
  local ws, root, saved, terms

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

  --- Every tab's label, left to right, after relabelling, in a strip given `room` columns.
  local function labels_at(room)
    ws.set_labels()
    return drawn_labels(ws.tab_strip(room))
  end

  before_each(function()
    pcall(vim.cmd, "tabonly")
    vim.t.workspace_slot = nil
    saved = { fishmonger = package.loaded["fishmonger"] }
    package.loaded["fishmonger"] = nil
    package.loaded["config.workspace"] = nil
    ws = require("config.workspace")
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
    ws.setup({ agent_worktrees = false })
    package.loaded["fishmonger"] = saved.fishmonger
    pcall(vim.cmd, "tabonly")
    vim.fn.delete(root, "rf")
  end)

  it("makes each tile a click target for its tabpage, the current one drawn selected", function()
    ws.set_labels()
    local strip = ws.tab_strip(200)
    assert.truthy(strip:find("%#BufferLineTab#%1T", 1, true))
    assert.truthy(strip:find("%#BufferLineTabSelected#%2T", 1, true))
    assert.truthy(strip:find("%999X", 1, true))
  end)

  it("shortens labels with coloured status glyphs only where uncoloured ones shorten", function()
    local first = vim.api.nvim_list_tabpages()[1]
    package.loaded["fishmonger"] = {
      tabs = function(t)
        return terms[t] or {}
      end,
    }
    for room = 70, 100 do
      terms[first] = { { slot = 2, icon = "✓" } }
      local plain = labels_at(room)
      terms[first] = { { slot = 2, icon = "✓", hl = "DiagnosticOk" } }
      assert.same(plain, labels_at(room), "at " .. room .. " columns")
    end
  end)

  it("keeps the repo on every tab when they exactly fit their room", function()
    assert.same(
      { "1 widget · helpful-teal · rkk/feature-cache-test-2", "2 .dotfiles - main" },
      labels_at(79)
    )
  end)

  it("drops the repo from every tab when they don't, and keeps the rest", function()
    assert.same({ "1 helpful-teal · rkk/feature-cache-test-2", "2 main" }, labels_at(78))
  end)

  it("keeps the repo once the labels pass two thirds of the screen but still fit", function()
    assert.same(
      { "1 widget · helpful-teal · rkk/feature-cache-test-2", "2 .dotfiles - main" },
      labels_at(100)
    )
  end)

  it("keeps the branch while the labels fit without the repo", function()
    assert.same({ "1 helpful-teal · rkk/feature-cache-test-2", "2 main" }, labels_at(58))
  end)

  it(
    "names each tab by its agent alone, a checkout without one by its repo, when that's short",
    function()
      assert.same({ "1 helpful-teal", "2 .dotfiles" }, labels_at(57))
    end
  )

  it("draws the shortest labels when even those don't fit", function()
    assert.same({ "1 helpful-teal", "2 .dotfiles" }, labels_at(10))
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

  it("keeps the session's name as the labels shorten", function()
    claude(vim.api.nvim_list_tabpages()[2], 1, 4245, "dotty")
    assert.same({ "1 helpful-teal · rkk/feature-cache-test-2", "2 dotty · main" }, labels_at(66))
    assert.same({ "1 helpful-teal", "2 dotty" }, labels_at(65))
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

  it("drops itself for a follow-up key that has its own mapping", function()
    local other_prefix = 0
    vim.keymap.set("n", "<C-b>", function()
      other_prefix = other_prefix + 1
    end)
    keys = { vim.api.nvim_replace_termcodes("<C-b>", true, false, true) }

    require("config.workspace").prefix({})
    vim.api.nvim_feedkeys("", "x", false)
    vim.keymap.del("n", "<C-b>")

    assert.equals(1, other_prefix)
  end)

  it("ignores a follow-up key with no mapping", function()
    keys = { "q" }
    local fed = 0
    local real_feedkeys = vim.api.nvim_feedkeys
    vim.api.nvim_feedkeys = function(_, _, _)
      fed = fed + 1
    end

    require("config.workspace").prefix({})
    vim.api.nvim_feedkeys = real_feedkeys

    assert.equals(0, fed)
  end)
end)

-- <M-b>e: a browser for a project that is NOT open yet, so it must start at
-- ~ rather than following the current buffer's file (the explorer default).
describe("workspace.explore", function()
  local saved_snacks, got

  before_each(function()
    saved_snacks = _G.Snacks
    got = nil
    _G.Snacks = { picker = {
      explorer = function(opts)
        got = opts
      end,
    } }
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
    assert.matches("^7 ", drawn_labels(ws.tab_strip(1000))[vim.fn.tabpagenr()])
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

  it(
    "opens the worktree picker on <M-b> w, a new branch on <M-b> b and the browser on <M-b> e without waiting for a number",
    function()
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
    end
  )

  it("closes a workspace without asking, even with a live agent", function()
    package.loaded["fishmonger"] = {
      tabs = function(_)
        return { { slot = 1, agent = { state = "permission" } } }
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
      agent_chat = package.loaded["config.agent_chat"],
    }
    _G.Snacks = { dashboard = { update = function() end } }
    package.loaded["util.sidebar"] = { open = function() end }
    package.loaded["fishmonger"] = { show = function(_, _) end }
    -- Terminal 1's agent chat takes slot 1 through fishmonger, as agent_chat.start does.
    package.loaded["config.agent_chat"] = {
      start = function(tab)
        package.loaded["fishmonger"].show(1, { tab = tab })
      end,
    }
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
    package.loaded["config.agent_chat"] = saved.agent_chat
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

  it(
    "with agent worktrees, names a worktree after its repo, its agent and the branch it has out",
    function()
      ws.setup({ agent_worktrees = true })
      report("/r/.git/worktrees/keen-heron", "/r/.git", "rkk/x")
      assert.equals("dotfiles · keen-heron · rkk/x", ws.display_name())
      report("/r/.git/worktrees/keen-heron", "/r/.git", "rkk/y")
      assert.equals("dotfiles · keen-heron · rkk/y", ws.display_name())
    end
  )

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

-- What terminal 1 runs: an agent chat, whatever the session it resumes ran in.
describe("workspace.open's terminal 1", function()
  local A = "5acea7d5-42e4-48ab-bae8-c06adaa57027"
  local ws, dir, saved, shells, chats

  before_each(function()
    pcall(vim.cmd, "tabonly")
    vim.t.workspace_slot = nil
    saved = {
      snacks = _G.Snacks,
      sidebar = package.loaded["util.sidebar"],
      fishmonger = package.loaded["fishmonger"],
      agent_chat = package.loaded["config.agent_chat"],
    }
    shells, chats = {}, {}
    _G.Snacks = { dashboard = { update = function() end } }
    package.loaded["util.sidebar"] = { open = function() end }
    package.loaded["fishmonger"] = {
      show = function(slot, opts)
        shells[#shells + 1] = { slot = slot, shell = opts.shell }
      end,
    }
    package.loaded["config.agent_chat"] = {
      start = function(tab, session_id, agent_name)
        chats[#chats + 1] = { tab = tab, session_id = session_id, agent_name = agent_name }
      end,
    }
    package.loaded["config.workspace"] = nil
    ws = require("config.workspace")
    ws.set_labels = function() end -- the tab label reads fishmonger and bufferline
    ws.agent_name = function() end -- asks git
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
    package.loaded["config.agent_chat"] = saved.agent_chat
  end)

  --- Opens `dir` in a new tab with `opts`, waiting for terminal 1 to start.
  local function open(opts)
    ws.open(dir, vim.tbl_extend("force", { tab = true }, opts))
    assert.is_true(vim.wait(1000, function()
      return #shells + #chats > 0
    end))
  end

  it("is an agent chat in the directory's newest session when there is nothing to resume", function()
    open({})
    assert.same({ { tab = ws.find(dir) } }, chats)
    assert.same({}, shells)
  end)

  it("resumes the session it is given as a chat", function()
    open({ resume = A })
    assert.same({ { tab = ws.find(dir), session_id = A } }, chats)
    assert.same({}, shells)
  end)

  it("starts its chat under the agent name its directory gives", function()
    ws.agent_name = function(d)
      return d == dir and "keen-heron" or nil
    end
    open({})
    assert.equals("keen-heron", chats[1].agent_name)
  end)

  it("is a plain shell without an agent", function()
    open({ agent = false })
    assert.same({ { slot = 1 } }, shells)
    assert.same({}, chats)
  end)
end)
