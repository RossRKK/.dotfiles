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
