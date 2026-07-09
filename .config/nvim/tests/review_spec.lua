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

  -- Callers pass raw nvim-tree node paths, which are not normalized.
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
      "edit",
      "discard_draft",
      "submit",
      "set_shown",
      "refresh",
      "has_comments",
    }) do
      assert.equals("function", type(comments[fn]), fn .. "() is missing")
    end
  end)
end)
