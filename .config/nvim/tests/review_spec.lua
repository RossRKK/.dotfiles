-- Pure logic in review/init.lua: the triage rollup and the path lookups.

local assert = require("luassert")
local review = require("review.init")

describe("review.verdict", function()
  ---@param state table<string, string> abs-path -> status
  local function verdict_of(state)
    review.status_by_path = state
    return review.verdict()
  end

  after_each(function()
    review.status_by_path = {}
  end)

  it("is nil when nothing changed", function()
    assert.is_nil(verdict_of({}))
  end)

  it("approves when every file is approved", function()
    assert.equals("APPROVE", verdict_of({ a = "approved", b = "approved" }))
  end)

  it("requests changes on a lone rejection", function()
    assert.equals("REQUEST_CHANGES", verdict_of({ a = "rejected" }))
  end)

  it("requests changes when a rejection sits among approvals", function()
    assert.equals("REQUEST_CHANGES", verdict_of({ a = "approved", b = "rejected" }))
  end)

  -- The mid-review property: while anything is still untriaged, a rejection does
  -- NOT harden into a blocking verdict -- an early submit goes out as COMMENT.
  it("stays COMMENT while an untriaged file outranks a rejection", function()
    assert.equals("COMMENT", verdict_of({ a = "changed", b = "rejected" }))
  end)

  it("stays COMMENT while an untriaged file sits among approvals", function()
    assert.equals("COMMENT", verdict_of({ a = "approved", b = "changed" }))
  end)

  it("treats revised as pending", function()
    assert.equals("COMMENT", verdict_of({ a = "revised" }))
  end)

  it("ranks revised above a rejection", function()
    assert.equals("COMMENT", verdict_of({ a = "revised", b = "rejected" }))
  end)
end)

describe("review.status", function()
  before_each(function()
    review.status_by_path = { ["/repo/a.lua"] = "approved" }
  end)

  after_each(function()
    review.status_by_path = {}
  end)

  it("is nil for a nil path", function()
    assert.is_nil(review.status(nil))
  end)

  it("is nil for an untracked path", function()
    assert.is_nil(review.status("/repo/other.lua"))
  end)

  it("looks up a tracked path", function()
    assert.equals("approved", review.status("/repo/a.lua"))
  end)

  -- Callers pass raw explorer node paths, which are not normalized.
  it("normalizes the path before looking it up", function()
    assert.equals("approved", review.status("/repo/sub/../a.lua"))
  end)
end)

describe("review.folder", function()
  before_each(function()
    review.folder_status = { ["/repo/src"] = "changed" }
  end)

  after_each(function()
    review.folder_status = {}
  end)

  it("is nil for a nil path", function()
    assert.is_nil(review.folder(nil))
  end)

  it("is nil for a directory with no rolled-up status", function()
    assert.is_nil(review.folder("/repo/docs"))
  end)

  it("looks up a rolled-up directory", function()
    assert.equals("changed", review.folder("/repo/src"))
  end)

  it("normalizes the path before looking it up", function()
    assert.equals("changed", review.folder("/repo/docs/../src"))
  end)
end)

describe("review.comments", function()
  local comments = require("review.comments")

  -- The keymaps and user commands bind straight to these; a rename or a
  -- require-time break should fail here rather than at first keypress.
  it("exposes the surface the keymaps bind to", function()
    for _, fn in ipairs({
      "comment",
      "reply",
      "resolve",
      "edit",
      "discard_draft",
      "submit",
      "set_shown",
      "refresh",
      "has_comments",
      "jump_comment",
    }) do
      assert.equals("function", type(comments[fn]), fn .. "() is missing")
    end
  end)
end)

describe("review.comments.remap_line", function()
  local remap = require("review.comments").remap_line

  -- Hunk tuples below are the real {start_a, count_a, start_b, count_b} that
  -- vim.diff(..., {result_type="indices"}) emits for the described edit against a
  -- five-line base "a\nb\nc\nd\ne\n" -- so these cases pin the convention, not
  -- just our arithmetic.

  it("is the identity with no changes", function()
    local row, tracked = remap({}, 3)
    assert.equals(3, row)
    assert.is_true(tracked)
  end)

  it("shifts a line down past an insertion above it", function()
    -- two lines inserted at the top: {0,0,1,2}
    local row, tracked = remap({ { 0, 0, 1, 2 } }, 3)
    assert.equals(5, row)
    assert.is_true(tracked)
  end)

  it("shifts a line up past a deletion above it", function()
    -- line 2 deleted: {2,1,1,0}
    local row, tracked = remap({ { 2, 1, 1, 0 } }, 3)
    assert.equals(2, row)
    assert.is_true(tracked)
  end)

  -- The property the user cared about: a line that only MOVED is tracked, never
  -- reported as drifted.
  it("tracks (not drifts) a moved-but-unchanged line", function()
    local _, tracked = remap({ { 0, 0, 1, 2 } }, 4)
    assert.is_true(tracked)
  end)

  it("leaves a line untouched when the insertion is below it", function()
    -- one line inserted after line 2: {2,0,3,1}
    assert.equals(1, remap({ { 2, 0, 3, 1 } }, 1))
    assert.equals(2, remap({ { 2, 0, 3, 1 } }, 2)) -- insertion sits after line 2
    assert.equals(4, remap({ { 2, 0, 3, 1 } }, 3)) -- line 3 pushed down one
  end)

  it("reports a line inside a change as untracked (drifted)", function()
    -- line 3 modified in place: {3,1,3,1}
    local row, tracked = remap({ { 3, 1, 3, 1 } }, 3)
    assert.is_false(tracked)
    assert.equals(3, row) -- anchored at the new hunk position
  end)

  it("accumulates deltas across several hunks below the line", function()
    -- +2 at top and -1 at old line 2, seen by a line after both.
    local row, tracked = remap({ { 0, 0, 1, 2 }, { 2, 1, 3, 0 } }, 4)
    assert.equals(5, row) -- 4 + 2 (insert) - 1 (delete)
    assert.is_true(tracked)
  end)
end)

describe("review.comments.next_anchor", function()
  local next_anchor = require("review.comments").next_anchor
  local rows = { 3, 7, 12 }

  it("finds the next row strictly past the cursor", function()
    assert.equals(7, next_anchor(rows, 3, 1)) -- on an anchor: skips to the next
    assert.equals(7, next_anchor(rows, 5, 1))
    assert.equals(3, next_anchor(rows, 1, 1))
  end)

  it("finds the previous row strictly before the cursor", function()
    assert.equals(3, next_anchor(rows, 7, -1)) -- on an anchor: skips to the prev
    assert.equals(7, next_anchor(rows, 9, -1))
    assert.equals(12, next_anchor(rows, 99, -1))
  end)

  it("does not wrap: nil when nothing lies that way", function()
    assert.is_nil(next_anchor(rows, 12, 1))
    assert.is_nil(next_anchor(rows, 3, -1))
    assert.is_nil(next_anchor({}, 5, 1))
  end)
end)
