-- Path/argument derivation and bookmark-list parsing in util/jjworkspace.lua.
-- The jj calls themselves are left to the real thing; these are the decisions
-- that would otherwise fail quietly as a mis-named or duplicated workspace.

local assert = require("luassert")
local jjw = require("util.jjworkspace")

describe("jjworkspace.path", function()
  it("flattens a bookmark path to one directory component", function()
    assert.equals("/dev/.jj-workspaces/repo/feat-x", jjw.path("/dev/repo", "feat/x"))
  end)

  -- The whole point: a secondary jj workspace can't hold a .git, so anything
  -- inside the repo makes git resolve upward and report the parent's state.
  it("puts the workspace outside the repo, never under it", function()
    local path = jjw.path("/dev/repo", "feat/x")
    assert.is_nil(path:match("^/dev/repo/"))
  end)
end)

describe("jjworkspace.add_args", function()
  it("names the workspace for the slug and parents it on the revision", function()
    assert.same(
      { "workspace", "add", "--name", "feat-x", "-r", "feat/x", "/ws/feat-x" },
      jjw.add_args("feat/x", "/ws/feat-x", "feat/x")
    )
  end)

  -- A fork sits on @, not on a bookmark: that is where the uncommitted work is.
  it("takes @ as the revision for a new line of work", function()
    assert.equals("@", jjw.add_args("rkk/new", "/ws/rkk-new", "@")[6])
  end)
end)

describe("jjworkspace.parse_candidates", function()
  --- One `jj bookmark list` line in the template's field order.
  local function row(name, remote, id, time, msg)
    return table.concat({ name, remote, id, time, msg }, "\t")
  end

  local out = table.concat({
    row("feat/x", "", "tzlrkkux", "1788603732", "the change"),
    row("feat/x", "git", "tzlrkkux", "1788603732", "the change"),
    row("feat/x", "origin", "tzlrkkux", "1788603732", "the change"),
    row("main", "", "twrmsxyx", "1788600000", "init"),
  }, "\n")

  it("drops the colocated git mirror, which is the same bookmark twice", function()
    local items = jjw.parse_candidates(out, {}, "/dev/repo")
    assert.equals(3, #items)
    for _, it in ipairs(items) do
      assert.is_not.equals("git/feat/x", it.branch)
    end
  end)

  it("qualifies a remote bookmark with its remote", function()
    local items = jjw.parse_candidates(out, {}, "/dev/repo")
    assert.equals("origin/feat/x", items[2].branch)
    assert.is_true(items[2].remote)
    assert.is_false(items[1].remote)
  end)

  -- Regression: jj() trims trailing whitespace off the output, so the last line
  -- of a listing whose description is empty loses its final tab. Requiring that
  -- separator dropped the bookmark from the picker, with nothing to show for it.
  it("keeps a trailing bookmark whose empty description lost its separator", function()
    local trimmed = table.concat({
      row("feat/x", "", "tzlrkkux", "1788603732", ""),
      "rkk/new\t\tytmxxssq\t1788604036",
    }, "\n")
    local items = jjw.parse_candidates(trimmed, {}, "/dev/repo")
    assert.equals(2, #items)
    assert.equals("rkk/new", items[2].branch)
    assert.equals("", items[2].msg)
  end)

  it("carries the commit time as the sort key", function()
    assert.equals(1788603732, jjw.parse_candidates(out, {}, "/dev/repo")[1].time)
  end)

  -- The picker marks these rows, and open() reuses them rather than adding a
  -- second workspace by a name jj would reject.
  it("points a bookmark at its existing workspace, by slug", function()
    local items = jjw.parse_candidates(out, { ["feat-x"] = true }, "/dev/repo")
    assert.equals("/dev/.jj-workspaces/repo/feat-x", items[1].worktree)
    assert.is_nil(items[#items].worktree)
  end)
end)
