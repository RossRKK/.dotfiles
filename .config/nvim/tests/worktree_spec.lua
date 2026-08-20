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

  -- A local branch called `foo/bar` must not be mistaken for remote `foo`'s
  -- branch `bar`: the local check has to come first.
  it("prefers a local branch that looks like a remote ref", function()
    assert.same(
      { "worktree", "add", "/r/.worktrees/origin-x", "origin/x" },
      worktree.add_args("origin/x", "/r/.worktrees/origin-x", { ["origin/x"] = true }, remotes)
    )
  end)
end)
