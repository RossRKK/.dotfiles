-- Path/argument derivation and bookmark-list parsing in util/jjworkspace.lua.
-- The jj calls themselves are left to the real thing; these are the decisions
-- that would otherwise fail quietly as a mis-named or duplicated workspace.

local assert = require("luassert")
local jjw = require("util.jjworkspace")

describe("jjworkspace.path", function()
  it("flattens a bookmark path to one directory component", function()
    assert.equals("/dev/repo/.worktrees/feat-x", jjw.path("/dev/repo", "feat/x"))
  end)

  -- Same layout as the git side: one project directory, so cwd-scoped tools
  -- (Claude Code's permission prompt among them) see the workspace as part of
  -- the repo. jj owns every VCS question under a .jj, so git finding the parent
  -- repo from in here does no harm.
  it("puts the workspace under the repo's .worktrees, like a git worktree", function()
    assert.truthy(jjw.path("/dev/repo", "feat/x"):match("^/dev/repo/%.worktrees/"))
  end)
end)

describe("jjworkspace.main_root", function()
  -- Regression: from inside .worktrees/a, the nearest .jj was a's own, so the
  -- next workspace landed at .worktrees/a/.worktrees/b.
  it("follows a secondary workspace's .jj/repo pointer to the main root", function()
    local files = { ["/dev/repo/.worktrees/a/.jj/repo"] = "../../../.jj/repo\n" }
    local root = jjw.main_root("/dev/repo/.worktrees/a", function(p)
      return files[p]
    end)
    assert.equals("/dev/repo", root)
  end)

  it("keeps the main workspace, whose .jj/repo is a directory", function()
    assert.equals("/dev/repo", jjw.main_root("/dev/repo", function()
      return nil
    end))
  end)
end)

describe("jjworkspace.lookup_revset", function()
  -- Regression: bookmarks() matches LOCAL bookmarks only. A bookmark that
  -- existed only as origin/x therefore looked new, and the workspace was forked
  -- off @ (master) with a local bookmark literally named origin/x on it.
  it("asks for remote bookmarks too", function()
    local rs = jjw.lookup_revset("infra/x")
    assert.truthy(rs:find('bookmarks(exact:"infra/x")', 1, true))
    assert.truthy(rs:find('remote_bookmarks(exact:"infra/x")', 1, true))
  end)

  it("is safe for an unknown name", function()
    assert.matches("^present%(", jjw.lookup_revset("nope"))
  end)
end)

describe("jjworkspace.parse_lookup", function()
  it("finds a remote-only bookmark and names its remote", function()
    local found = jjw.parse_lookup("infra/x@origin\n", "infra/x")
    assert.is_false(found.is_local)
    assert.same({ "origin" }, found.remotes)
  end)

  it("finds a local bookmark that is also on a remote, minus the git mirror", function()
    local found = jjw.parse_lookup("master\nmaster@origin\nmaster@git\n", "master")
    assert.is_true(found.is_local)
    assert.same({ "origin" }, found.remotes)
  end)

  -- Other bookmarks on the same commit come through the template as well.
  it("ignores other bookmarks that share the commit", function()
    local found = jjw.parse_lookup("cv-2026.09.6\nmaster@origin\n", "master")
    assert.is_false(found.is_local)
    assert.same({ "origin" }, found.remotes)
  end)

  it("reports nothing for an unknown name", function()
    local found = jjw.parse_lookup("", "nope")
    assert.is_false(found.is_local)
    assert.same({}, found.remotes)
  end)
end)

describe("jjworkspace.track_args", function()
  it("tracks the bookmark on the remote it was found on", function()
    assert.same({ "bookmark", "track", "infra/x@origin" }, jjw.track_args("infra/x", "origin"))
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
    assert.equals("/dev/repo/.worktrees/feat-x", items[1].worktree)
    assert.is_nil(items[#items].worktree)
  end)
end)
