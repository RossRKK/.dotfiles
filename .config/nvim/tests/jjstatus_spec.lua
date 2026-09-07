-- The pure half of util/jjstatus.lua: how jj's output becomes neo-tree's
-- path -> code map. The jj calls and the neo-tree registration are left to the
-- real thing; these are the decisions that would otherwise show up as a wrong
-- glyph or a whole workspace painted "ignored".

local assert = require("luassert")
local js = require("util.jjstatus")

local root = "/dev/repo/.worktrees/x"

describe("jjstatus.parse_summary", function()
  it("maps jj letters to worktree-column codes on absolute paths", function()
    local s = js.parse_summary("M src/a.lua\nA src/new.lua\nD gone.txt\n", root)
    assert.equals(".M", s[root .. "/src/a.lua"])
    assert.equals(".A", s[root .. "/src/new.lua"])
    assert.equals(".D", s[root .. "/gone.txt"])
  end)

  it("bubbles the first code up to, but not including, the root", function()
    local s = js.parse_summary("A deep/er/new.lua\nM deep/other.lua\n", root)
    assert.equals(".A", s[root .. "/deep/er"])
    assert.equals(".A", s[root .. "/deep"]) -- first to arrive wins
    assert.is_nil(s[root])
    assert.is_nil(s["/dev/repo/.worktrees"])
  end)

  it("uses the new name of a rename", function()
    local s = js.parse_summary("R old.lua => lib/new.lua\n", root)
    assert.equals(".R", s[root .. "/lib/new.lua"])
    assert.is_nil(s[root .. "/old.lua"])
  end)

  it("ignores lines it does not understand", function()
    local s = js.parse_summary("Working copy changes:\n\n", root)
    assert.same({}, s)
  end)
end)

describe("jjstatus.tracked_set", function()
  it("contains each file and every directory above it, below the root", function()
    local t = js.tracked_set("src/a.lua\nREADME.md\n", root)
    assert.is_true(t[root .. "/src/a.lua"])
    assert.is_true(t[root .. "/src"])
    assert.is_true(t[root .. "/README.md"])
    assert.is_nil(t[root])
  end)
end)

describe("jjstatus.mark_ignored", function()
  local tracked = js.tracked_set("src/a.lua\n", root)

  it("marks shown paths jj does not track as ignored", function()
    local s = js.mark_ignored({}, tracked, {
      root .. "/src",
      root .. "/src/a.lua",
      root .. "/target",
      root .. "/.jj",
      root .. "/src/a.lua.orig",
    }, root)
    assert.is_nil(s[root .. "/src"])
    assert.is_nil(s[root .. "/src/a.lua"])
    assert.equals("!", s[root .. "/target"])
    assert.equals("!", s[root .. "/.jj"])
    assert.equals("!", s[root .. "/src/a.lua.orig"])
  end)

  -- The whole point: a file inside a secondary workspace under .worktrees/ is
  -- tracked by jj, so it is NOT ignored, whatever git's global excludes say
  -- about its parent directory.
  it("never marks the root or a tracked file, even under a git-ignored dir", function()
    local s = js.mark_ignored({}, tracked, { root, root .. "/src/a.lua" }, root)
    assert.same({}, s)
  end)

  it("leaves an existing change code alone", function()
    local s = js.mark_ignored(
      { [root .. "/new.lua"] = ".A" },
      tracked,
      { root .. "/new.lua" },
      root
    )
    assert.equals(".A", s[root .. "/new.lua"])
  end)
end)
