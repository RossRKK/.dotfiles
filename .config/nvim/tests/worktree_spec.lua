-- Worktree path/flag derivation in util/worktree.lua. The parts that talk to git
-- are left to the real thing; these are the decisions that go wrong silently.

local assert = require("luassert")
local worktree = require("util.worktree")

describe("worktree.slug", function()
  it("flattens a branch path to one directory component", function()
    assert.equals("feat-thing", worktree.slug("feat/thing"))
  end)

  it("drops the remotes/ prefix", function()
    assert.equals("origin-main", worktree.slug("remotes/origin/main"))
  end)
end)

describe("worktree.resolve", function()
  local locals = { main = true }
  local refs = { ["origin/main"] = true, ["origin/feat/x"] = true, ["fork/feat/x"] = true }

  it("keeps an existing local branch as-is", function()
    assert.equals("main", worktree.resolve("main", locals, refs))
  end)

  it("keeps a remote-qualified ref as-is (with remotes/ stripped)", function()
    assert.equals("origin/feat/x", worktree.resolve("remotes/origin/feat/x", locals, refs))
  end)

  -- The paste-from-GitHub case: a bare branch name that only exists remotely.
  it("qualifies a bare name with origin over other remotes", function()
    assert.equals("origin/feat/x", worktree.resolve("feat/x", locals, refs))
  end)

  it("falls back to any remote carrying the branch", function()
    assert.equals("fork/feat/y", worktree.resolve("feat/y", locals, { ["fork/feat/y"] = true }))
  end)

  it("returns nil for a name nothing has", function()
    assert.is_nil(worktree.resolve("new/thing", locals, refs))
  end)
end)

-- The worktree directory (and thus the project tab) is named after the local
-- branch that ends up checked out, never the remote-qualified ref.
describe("worktree.local_name", function()
  local locals = { main = true, ["origin/x"] = true }
  local remotes = { origin = true }

  it("strips the remote qualifier from a remote ref", function()
    assert.equals("feat/x", worktree.local_name("origin/feat/x", locals, remotes))
    assert.equals("feat/x", worktree.local_name("remotes/origin/feat/x", locals, remotes))
  end)

  it("keeps a local branch as-is", function()
    assert.equals("main", worktree.local_name("main", locals, remotes))
  end)

  it("prefers a local branch that looks like a remote ref", function()
    assert.equals("origin/x", worktree.local_name("origin/x", locals, remotes))
  end)

  it("keeps a slashed name that matches no remote", function()
    assert.equals("new/thing", worktree.local_name("new/thing", locals, remotes))
  end)
end)

describe("worktree.add_args", function()
  local locals = { main = true }
  local remotes = { origin = true }

  it("checks out an existing local branch", function()
    assert.same(
      { "worktree", "add", "/r/.worktrees/main", "main" },
      worktree.add_args("main", "/r/.worktrees/main", locals, remotes)
    )
  end)

  it("creates a tracking branch for a remote ref", function()
    assert.same(
      {
        "worktree",
        "add",
        "--track",
        "-b",
        "feat/x",
        "/r/.worktrees/origin-feat-x",
        "origin/feat/x",
      },
      worktree.add_args("remotes/origin/feat/x", "/r/.worktrees/origin-feat-x", locals, remotes)
    )
  end)

  it("creates a new branch off HEAD for an unknown name", function()
    assert.same(
      { "worktree", "add", "-b", "new/thing", "/r/.worktrees/new-thing" },
      worktree.add_args("new/thing", "/r/.worktrees/new-thing", locals, remotes)
    )
  end)

  -- Picking `origin/x` when a local branch `x` already exists: -b would fail
  -- with "branch already exists", so the local branch is checked out instead.
  it("reuses an existing local branch for its remote ref", function()
    assert.same(
      { "worktree", "add", "/r/.worktrees/x", "x" },
      worktree.add_args("origin/x", "/r/.worktrees/x", { x = true }, remotes)
    )
  end)

  -- A local branch called `foo/bar` must not be mistaken for remote `foo`'s
  -- branch `bar`: the local check has to come first.
  it("prefers a local branch that looks like a remote ref", function()
    assert.same(
      { "worktree", "add", "/r/.worktrees/origin-x", "origin/x" },
      worktree.add_args("origin/x", "/r/.worktrees/origin-x", { ["origin/x"] = true }, remotes)
    )
  end)
end)

-- Forking (<leader>tf) must branch off the worktree the user is sitting in, not
-- the main worktree's HEAD -- which is what add_args's new-branch case gives,
-- since M.open runs git in the repo root. Hence the explicit base commit.
describe("worktree.fork_args", function()
  it("creates the branch at the given base commit", function()
    assert.same(
      { "worktree", "add", "-b", "feat/y", "/r/.worktrees/feat-y", "abc123" },
      worktree.fork_args("feat/y", "/r/.worktrees/feat-y", "abc123")
    )
  end)
end)

-- The prompt's pre-filled suggestion: always under rkk/, named after the branch
-- being forked, and never a name git would reject as existing.
describe("worktree.fork_name", function()
  it("prefixes and suffixes a plain branch", function()
    assert.equals("rkk/main-fork", worktree.fork_name("main", {}))
  end)

  it("does not double an existing rkk/ prefix", function()
    assert.equals("rkk/feat-x-fork", worktree.fork_name("rkk/feat-x", {}))
  end)

  it("numbers past taken names", function()
    local locals = { ["rkk/main-fork"] = true, ["rkk/main-fork-2"] = true }
    assert.equals("rkk/main-fork-3", worktree.fork_name("main", locals))
  end)

  it("falls back for a detached HEAD", function()
    assert.equals("rkk/fork", worktree.fork_name("HEAD", {}))
    assert.equals("rkk/fork", worktree.fork_name(nil, {}))
  end)
end)

describe("worktree.fork_cmd", function()
  it("resumes the session as a fork", function()
    assert.equals("claude --resume 0f1e2d3c --fork-session", worktree.fork_cmd("0f1e2d3c"))
  end)
end)

-- Git's --progress lines drive the status toast during a checkout (seconds on a
-- large tree, longer cold). Anything else on stderr must not be mistaken for one.
describe("worktree.progress", function()
  it("reads the percentage and phase from a progress line", function()
    local pct, phase = worktree.progress("Updating files:  45% (3600/7941)")
    assert.equals(45, pct)
    assert.equals("Updating files", phase)
  end)

  it("handles fetch phases too", function()
    assert.equals(12, worktree.progress("Receiving objects:  12% (120/1000), 1.2 MiB | 3 MiB/s"))
  end)

  it("ignores non-progress output", function()
    assert.is_nil(worktree.progress("Preparing worktree (new branch 'x')"))
    assert.is_nil(worktree.progress("fatal: '.worktrees/x' already exists"))
    assert.is_nil(worktree.progress(""))
  end)
end)

describe("worktree.order", function()
  local function names(items)
    return vim.tbl_map(function(it)
      return it.branch
    end, items)
  end

  it("puts worktrees first, most recently opened first", function()
    local items = {
      { branch = "old", time = 300, worktree = "/w/old" },
      { branch = "hot", time = 100, worktree = "/w/hot" },
      { branch = "main", time = 900 },
    }
    local out = names(worktree.order(items, { ["/w/hot"] = 20, ["/w/old"] = 10 }))
    assert.are.same({ "hot", "old", "main" }, out)
  end)

  it("orders never-opened worktrees by commit date after opened ones", function()
    local items = {
      { branch = "a", time = 900, worktree = "/w/a" },
      { branch = "b", time = 100, worktree = "/w/b" },
      { branch = "c", time = 500, worktree = "/w/c" },
    }
    local out = names(worktree.order(items, { ["/w/b"] = 5 }))
    assert.are.same({ "b", "a", "c" }, out)
  end)

  it("orders plain branches by commit date, newest first", function()
    local items = {
      { branch = "x", time = 1 },
      { branch = "z", time = 3 },
      { branch = "y", time = 2 },
    }
    assert.are.same({ "z", "y", "x" }, names(worktree.order(items, {})))
  end)

  it("drops a remote ref that duplicates a local branch", function()
    local items = {
      { branch = "origin/x", time = 5, remote = true },
      { branch = "x", time = 1 },
      { branch = "origin/only-remote", time = 2, remote = true },
      { branch = "feat/local", time = 3 },
    }
    assert.are.same({ "feat/local", "origin/only-remote", "x" }, names(worktree.order(items, {})))
  end)

  it("shows a remote ref by its bare name, once across remotes, origin first", function()
    local items = {
      { branch = "fork/x", time = 9, remote = true },
      { branch = "origin/x", time = 1, remote = true },
    }
    local out = worktree.order(items, {})
    assert.are.same(1, #out)
    assert.are.same("origin/x", out[1].branch)
    assert.are.same("x", out[1].name)
  end)
end)

describe("worktree.path", function()
  it("uses wherever git already has the branch checked out", function()
    assert.equals("/elsewhere/x", worktree.path("/repo", "feat/x", { ["feat/x"] = "/elsewhere/x" }))
  end)

  it("puts a new one under .worktrees, flattened", function()
    assert.equals("/repo/.worktrees/feat-x", worktree.path("/repo", "feat/x", { main = "/repo" }))
  end)
end)

-- Agent worktrees: named after the agent, never reusing a name that a worktree
-- or Claude's history already has.
describe("worktree.claude_project", function()
  it("names a directory's Claude state the way Claude does", function()
    assert.equals(
      "/c/projects/-home-me--dotfiles--worktrees-keen-heron",
      worktree.claude_project("/c/projects", "/home/me/.dotfiles/.worktrees/keen-heron")
    )
  end)
end)

describe("worktree.free_name", function()
  it("takes the first candidate that isn't taken", function()
    local taken = { ["keen-heron"] = true }
    assert.equals(
      "calm-otter",
      worktree.free_name({ "keen-heron", "calm-otter", "bold-yak" }, function(n)
        return taken[n] == true
      end)
    )
  end)

  it("gives nothing when every candidate is taken", function()
    assert.is_nil(worktree.free_name({ "keen-heron" }, function()
      return true
    end))
  end)
end)

-- M.target against a real repo, with petname stubbed to a fixed list.
describe("worktree.target", function()
  local dir, repo, projects, saved_path

  local function git(...)
    local cmd = { "git", "-c", "user.name=t", "-c", "user.email=t@t", ... }
    local res = vim.system(cmd, { cwd = repo, text = true }):wait()
    assert(res.code == 0, table.concat(cmd, " ") .. ": " .. (res.stderr or ""))
  end

  before_each(function()
    dir = vim.fn.tempname()
    repo, projects = dir .. "/repo", dir .. "/projects"
    vim.fn.mkdir(repo, "p")
    vim.fn.mkdir(dir .. "/bin", "p")
    local names = "printf 'keen-heron\\ncalm-otter\\nbold-yak\\n'"
    vim.fn.writefile({ "#!/bin/sh", names }, dir .. "/bin/petname")
    vim.fn.setfperm(dir .. "/bin/petname", "rwxr-xr-x")
    saved_path = vim.env.PATH
    vim.env.PATH = dir .. "/bin:" .. vim.env.PATH
    git("init", "-q", "-b", "main")
    git("commit", "-q", "--allow-empty", "-m", "init")
    git("branch", "feat/x")
    worktree.setup({ agent_worktrees = true, claude_projects = projects })
  end)

  after_each(function()
    vim.env.PATH = saved_path
    worktree.setup({ agent_worktrees = false })
    vim.fn.delete(dir, "rf")
  end)

  it("puts a branch no worktree has into a new worktree named after its agent", function()
    local t = assert(worktree.target("feat/x", repo))
    assert.equals("create", t.kind)
    assert.equals("keen-heron", t.name)
    assert.equals(repo .. "/.worktrees/keen-heron", t.path)
  end)

  it("skips a name a worktree directory or Claude's history already has", function()
    vim.fn.mkdir(repo .. "/.worktrees/keen-heron", "p")
    vim.fn.mkdir(worktree.claude_project(projects, repo .. "/.worktrees/calm-otter"), "p")
    assert.equals("bold-yak", assert(worktree.target("feat/x", repo)).name)
  end)

  it("opens the worktree that has the branch checked out", function()
    local t = assert(worktree.target("main", repo))
    assert.equals("open", t.kind)
    assert.equals(vim.uv.fs_realpath(repo), vim.uv.fs_realpath(t.path))
    assert.is_nil(t.name)
  end)

  it("with agent worktrees off, names the worktree after the branch", function()
    worktree.setup({ agent_worktrees = false })
    local t = assert(worktree.target("feat/x", repo))
    assert.equals("create", t.kind)
    assert.equals(repo .. "/.worktrees/feat-x", t.path)
    assert.is_nil(t.name)
  end)
end)

-- Which worktree a branch belongs to: the one whose HEAD reflog last had it,
-- from real reflogs (git's own formats) written at fixed times.
describe("worktree ownership", function()
  local repo

  --- git in `cwd`, its reflog entries stamped `time`.
  local function git(cwd, time, ...)
    local cmd = { "git", "-c", "user.name=t", "-c", "user.email=t@t", ... }
    local env = { GIT_COMMITTER_DATE = ("@%d +0000"):format(time) }
    local res = vim.system(cmd, { cwd = cwd, env = env, text = true }):wait()
    assert(res.code == 0, table.concat(cmd, " ") .. ": " .. (res.stderr or ""))
  end

  local function wt(name)
    return repo .. "/.worktrees/" .. name
  end

  local function reflog(name)
    local gitdir = vim.fn.readfile(wt(name) .. "/.git")[1]:match("^gitdir: (.+)$")
    return table.concat(vim.fn.readfile(gitdir .. "/logs/HEAD"), "\n")
  end

  before_each(function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. "/repo", "p")
    repo = vim.uv.fs_realpath(dir .. "/repo")
    git(repo, 1, "init", "-q", "-b", "main")
    git(repo, 1, "commit", "-q", "--allow-empty", "-m", "init")
    git(repo, 1, "branch", "a")
    git(repo, 1, "branch", "x")
    git(repo, 2, "commit", "-q", "--allow-empty", "-m", "on main")
    git(repo, 100, "worktree", "add", "-q", wt("one"), "a")
    git(wt("one"), 200, "checkout", "-q", "x")
    worktree.setup({ agent_worktrees = true })
  end)

  after_each(function()
    worktree.setup({ agent_worktrees = false })
    vim.fn.delete(vim.fs.dirname(repo), "rf")
  end)

  it("counts a checkout for the branch left and the branch moved to", function()
    local at = worktree.checkouts(reflog("one"))
    assert.equals(200, at.a)
    assert.equals(200, at.x)
  end)

  it("counts a rebase for the branch it returns to", function()
    git(wt("one"), 300, "checkout", "-q", "a")
    git(wt("one"), 350, "commit", "-q", "--allow-empty", "-m", "on a")
    git(wt("one"), 400, "rebase", "-q", "main")
    assert.truthy(reflog("one"):find("rebase (finish): returning to refs/heads/a", 1, true))
    assert.equals(400, worktree.checkouts(reflog("one")).a)
  end)

  it("reads an interactive rebase's finish too", function()
    local log = "0000000 1111111 t <t@t> 400 +0000\trebase -i (finish): returning to refs/heads/a"
    assert.equals(400, worktree.checkouts(log).a)
  end)

  it("knows no branch from a worktree add alone", function()
    git(repo, 300, "worktree", "add", "-q", wt("two"), "main~1")
    assert.same({}, worktree.checkouts(reflog("two")))
  end)

  it("gives the branch to the worktree that had it most recently", function()
    git(repo, 300, "worktree", "add", "-q", "--detach", wt("two"))
    git(wt("two"), 400, "checkout", "-q", "a")
    git(wt("two"), 500, "checkout", "-q", "--detach")
    assert.equals(wt("two"), worktree.owner("a", { wt("one"), wt("two") }))

    git(wt("one"), 600, "checkout", "-q", "a")
    git(wt("one"), 700, "checkout", "-q", "x")
    assert.equals(wt("one"), worktree.owner("a", { wt("one"), wt("two") }))
    assert.is_nil(worktree.owner("main", { wt("one"), wt("two") }))
  end)

  it("checks the branch out again where it was last, when no Claude runs there", function()
    local t = assert(worktree.target("a", repo))
    assert.equals("switch", t.kind)
    assert.equals(wt("one"), t.path)
    assert.equals("a", t.local_branch)
  end)

  it("never gives a branch to the main checkout, which is yours", function()
    git(repo, 300, "checkout", "-q", "a")
    git(repo, 400, "checkout", "-q", "main")
    assert.equals(wt("one"), assert(worktree.target("a", repo)).path)
  end)

  it("opens the branch where it is checked out now, whoever had it before", function()
    git(repo, 300, "worktree", "add", "-q", wt("two"), "a")
    assert.same({ "open", wt("two") }, {
      assert(worktree.target("a", repo)).kind,
      assert(worktree.target("a", repo)).path,
    })
  end)

  describe("with a Claude running in the owner's workspace", function()
    local saved, sent

    before_each(function()
      local workspace = require("config.workspace")
      saved = {
        fishmonger = package.loaded["fishmonger"],
        find = workspace.find,
        chan_send = vim.api.nvim_chan_send,
      }
      vim.cmd("tabnew")
      local tab = vim.api.nvim_get_current_tabpage()
      vim.cmd("tabprevious")
      workspace.find = function(path)
        return path == wt("one") and tab or nil
      end
      package.loaded["fishmonger"] = {
        tabs = function(t)
          return t == tab and { { slot = 1 }, { slot = 2, agent = { state = "working" } } } or {}
        end,
        show = function(_, _) end,
      }
      sent = {}
      vim.api.nvim_chan_send = function(chan, data)
        sent[#sent + 1] = { chan = chan, data = data }
      end
    end)

    after_each(function()
      package.loaded["fishmonger"] = saved.fishmonger
      require("config.workspace").find = saved.find
      vim.api.nvim_chan_send = saved.chan_send
      pcall(vim.cmd, "tabonly")
    end)

    it("asks that Claude to check it out, typed into its prompt but not submitted", function()
      local t = assert(worktree.target("a", repo))
      assert.equals("ask", t.kind)
      assert.equals(2, t.agent.slot)

      local shown
      package.loaded["fishmonger"].show = function(slot, _)
        shown = slot
      end
      worktree.go(t, {})
      assert.equals(t.agent.tab, vim.api.nvim_get_current_tabpage())
      assert.equals(2, shown)
      assert.equals(1, #sent)
      assert.truthy(sent[1].data:find("git checkout a", 1, true))
      assert.is_nil(sent[1].data:find("[\r\n]"))
    end)

    it("in the background, types it and leaves you where you were", function()
      local origin = vim.api.nvim_get_current_tabpage()
      worktree.go(assert(worktree.target("a", repo)), { background = true })
      assert.equals(1, #sent)
      assert.equals(origin, vim.api.nvim_get_current_tabpage())
    end)
  end)
end)
