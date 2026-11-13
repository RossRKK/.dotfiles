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
    assert.same({
      "worktree",
      "add",
      "--track",
      "-b",
      "feat/x",
      "/r/.worktrees/origin-feat-x",
      "origin/feat/x",
    }, worktree.add_args(
      "remotes/origin/feat/x",
      "/r/.worktrees/origin-feat-x",
      locals,
      remotes
    ))
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

  it("makes a new agent worktree even for a branch another agent's worktree had before", function()
    git("worktree", "add", "-q", repo .. "/.worktrees/old-agent", "feat/x")
    git("-C", repo .. "/.worktrees/old-agent", "checkout", "-q", "--detach")
    local t = assert(worktree.target("feat/x", repo))
    assert.equals("create", t.kind)
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

describe("worktree.buf_path", function()
  it("gives a terminal the directory it started in", function()
    assert.equals("/repo/.worktrees/x", worktree.buf_path("term:///repo/.worktrees/x//4242:fish"))
  end)

  it("gives any other buffer its own name", function()
    assert.equals("/repo/a.lua", worktree.buf_path("/repo/a.lua"))
  end)
end)

-- M.remove against a real repo: a worktree tab as config.workspace opens one
-- (a numbered tabpage, :tcd into the checkout), with a terminal job running there.
describe("worktree.remove", function()
  local dir, repo, wt, saved_confirm
  vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/lazy/snacks.nvim")

  local function git(cwd, ...)
    local cmd = { "git", "-c", "user.name=t", "-c", "user.email=t@t", ... }
    local res = vim.system(cmd, { cwd = cwd, text = true }):wait()
    assert(res.code == 0, table.concat(cmd, " ") .. ": " .. (res.stderr or ""))
    return vim.trim(res.stdout)
  end

  local function confirm_with(choice)
    vim.fn.confirm = function(_, _, _, _)
      return choice
    end
  end

  local function open_tab(path)
    vim.cmd("tabnew")
    vim.cmd.tcd(vim.fn.fnameescape(path))
    vim.api.nvim_tabpage_set_var(0, "workspace_slot", 2)
    return vim.api.nvim_get_current_tabpage()
  end

  local function gone()
    return vim.wait(5000, function()
      return vim.uv.fs_stat(wt) == nil
    end)
  end

  before_each(function()
    dir = vim.uv.fs_realpath(vim.fn.tempname()) or vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    dir = vim.uv.fs_realpath(dir)
    repo, wt = dir .. "/repo", dir .. "/repo/.worktrees/feat-x"
    vim.fn.mkdir(repo, "p")
    vim.fn.writefile({ "hi" }, repo .. "/README")
    git(repo, "init", "-q", "-b", "main")
    git(repo, "add", "README")
    git(repo, "commit", "-q", "-m", "init")
    git(repo, "worktree", "add", "-q", "-b", "feat/x", wt)
    vim.cmd.cd(vim.fn.fnameescape(repo))
    saved_confirm = vim.fn.confirm
  end)

  after_each(function()
    vim.fn.confirm = saved_confirm
    vim.cmd("silent! tabonly!")
    vim.cmd("silent! %bwipeout!")
    vim.fn.delete(dir, "rf")
  end)

  it("stops its jobs, wipes its buffers everywhere, closes the tab, then removes it", function()
    vim.cmd.edit(vim.fn.fnameescape(wt .. "/README")) -- in the first tab: wiped from every tab
    local file = vim.api.nvim_get_current_buf()
    local tab = open_tab(wt)
    vim.cmd("enew")
    local chan = vim.fn.jobstart({ "sleep", "600" }, { term = true })
    local term, pid = vim.api.nvim_get_current_buf(), vim.fn.jobpid(chan)
    confirm_with(1) -- asked only if something would be lost: it isn't

    worktree.remove()

    assert.is_false(vim.api.nvim_tabpage_is_valid(tab))
    assert.is_false(vim.api.nvim_buf_is_valid(term))
    assert.is_false(vim.api.nvim_buf_is_valid(file))
    assert.is_not_nil(select(2, vim.uv.kill(pid, 0)), "the terminal's process is still running")
    assert.is_true(gone())
    assert.equals("feat/x", git(repo, "branch", "--list", "feat/x"):gsub("^[*+ ]+", ""))
  end)

  it("leaves a dirty worktree alone unless confirmed, then forces it", function()
    vim.fn.writefile({ "wip" }, wt .. "/untracked")
    local tab = open_tab(wt)
    confirm_with(2)
    worktree.remove()
    assert.is_true(vim.api.nvim_tabpage_is_valid(tab))
    assert.is_not_nil(vim.uv.fs_stat(wt .. "/untracked"))

    confirm_with(1)
    worktree.remove()
    assert.is_false(vim.api.nvim_tabpage_is_valid(tab))
    assert.is_true(gone())
  end)

  it("does nothing in a tab on the main checkout", function()
    local tab = open_tab(repo)
    worktree.remove()
    assert.is_true(vim.api.nvim_tabpage_is_valid(tab))
    assert.is_not_nil(vim.uv.fs_stat(wt))
  end)

  it("moves a global cwd inside the checkout to the main one", function()
    vim.cmd.cd(vim.fn.fnameescape(wt))
    open_tab(wt)
    worktree.remove()
    assert.equals(repo, vim.fn.getcwd(-1, -1))
    assert.is_true(gone())
  end)
end)
