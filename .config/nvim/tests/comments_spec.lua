-- The tree-decorator set in review/comments.lua: which paths light up as
-- "has comments" once live comments and unsent drafts are folded together.

local assert = require("luassert")
local comments = require("review.comments")

describe("comments.rebuild_marked", function()
  before_each(function()
    comments.by_path = {}
    comments.drafts = {}
    comments.marked = {}
  end)

  it("is empty when there are no comments or drafts", function()
    comments.rebuild_marked("/repo")
    assert.same({}, comments.marked)
  end)

  -- The decorator paints directories too, so an icon on a nested file has to
  -- propagate up every ancestor for the collapsed tree to show it.
  it("marks a commented file and every ancestor up to the root", function()
    comments.by_path = { ["src/a/b.lua"] = { { line = 1 } } }
    comments.rebuild_marked("/repo")

    assert.same({
      ["/repo"] = true,
      ["/repo/src"] = true,
      ["/repo/src/a"] = true,
      ["/repo/src/a/b.lua"] = true,
    }, comments.marked)
  end)

  it("marks a file at the repo root", function()
    comments.by_path = { ["README.md"] = { { line = 1 } } }
    comments.rebuild_marked("/repo")

    assert.same({ ["/repo"] = true, ["/repo/README.md"] = true }, comments.marked)
  end)

  it("marks drafts as well as live comments", function()
    comments.drafts = { ["src/draft.lua"] = { { line = 2, body = "hi" } } }
    comments.rebuild_marked("/repo")

    assert.is_true(comments.marked["/repo/src/draft.lua"])
    assert.is_true(comments.marked["/repo/src"])
  end)

  -- Discarding the last draft on a file leaves an empty list behind rather than
  -- removing the key; that file must stop being marked.
  it("ignores a file whose draft list is empty", function()
    comments.drafts = { ["src/empty.lua"] = {} }
    comments.rebuild_marked("/repo")

    assert.same({}, comments.marked)
  end)

  it("unions live comments and drafts", function()
    comments.by_path = { ["src/live.lua"] = { { line = 1 } } }
    comments.drafts = { ["docs/draft.md"] = { { line = 1, body = "hi" } } }
    comments.rebuild_marked("/repo")

    assert.is_true(comments.marked["/repo/src/live.lua"])
    assert.is_true(comments.marked["/repo/docs/draft.md"])
    assert.is_true(comments.marked["/repo"])
  end)

  it("replaces the previous set rather than accumulating", function()
    comments.by_path = { ["gone.lua"] = { { line = 1 } } }
    comments.rebuild_marked("/repo")
    assert.is_true(comments.marked["/repo/gone.lua"])

    comments.by_path = { ["kept.lua"] = { { line = 1 } } }
    comments.rebuild_marked("/repo")

    assert.is_nil(comments.marked["/repo/gone.lua"])
    assert.is_true(comments.marked["/repo/kept.lua"])
  end)

  it("normalizes a root given with a trailing slash", function()
    comments.by_path = { ["a.lua"] = { { line = 1 } } }
    comments.rebuild_marked("/repo/")

    assert.is_true(comments.marked["/repo/a.lua"])
  end)
end)
