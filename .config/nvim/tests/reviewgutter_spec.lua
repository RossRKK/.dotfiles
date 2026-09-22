-- util/reviewgutter: the shared review gutter must be exactly two cells wide on
-- every row while review mode is on, and absent while it is off, so rows never
-- shift against their neighbours.

local assert = require("luassert")

local fake_triage, fake_nitpick, fake_components
local function reset()
  fake_triage = {
    on = false,
    icons = { approved = { text = "V", hl = "ReviewApproved" } },
    by_path = {},
    by_dir = {},
  }
  fake_triage.is_enabled = function()
    return fake_triage.on
  end
  fake_triage.status = function(p)
    return fake_triage.by_path[p]
  end
  fake_triage.folder = function(p)
    return fake_triage.by_dir[p]
  end
  fake_nitpick = { marked = {} }
  fake_nitpick.has_comments = function(p)
    return fake_nitpick.marked[p] == true
  end
  fake_components = {
    icon = function()
      return { text = "I ", highlight = "NeoTreeFileIcon" }
    end,
  }
  package.loaded["triage"] = fake_triage
  package.loaded["nitpick"] = fake_nitpick
  package.loaded["neo-tree.sources.common.components"] = fake_components
  package.loaded["util.reviewgutter"] = nil
  return require("util.reviewgutter")
end

local file = { type = "file", path = "/r/a.lua" }
local dir = { type = "directory", path = "/r/d" }

describe("reviewgutter.gutter", function()
  it("draws nothing while review mode is off, even for a marked file", function()
    local g = reset()
    fake_triage.by_path[file.path] = "approved"
    fake_nitpick.marked[file.path] = true
    assert.same({ text = "" }, g.gutter({}, file, {}))
  end)

  it("reserves two blank cells for an unmarked row while review mode is on", function()
    local g = reset()
    fake_triage.on = true
    assert.same({ text = "  " }, g.gutter({}, file, {}))
  end)

  it("draws the triage glyph plus a space for a marked file", function()
    local g = reset()
    fake_triage.on = true
    fake_triage.by_path[file.path] = "approved"
    assert.same({ text = "V ", highlight = "ReviewApproved" }, g.gutter({}, file, {}))
  end)

  it("uses the rolled-up folder status for a directory", function()
    local g = reset()
    fake_triage.on = true
    fake_triage.by_dir[dir.path] = "approved"
    assert.same({ text = "V ", highlight = "ReviewApproved" }, g.gutter({}, dir, {}))
  end)

  it("lets the comment bubble win over the triage status", function()
    local g = reset()
    fake_triage.on = true
    fake_triage.by_path[file.path] = "approved"
    fake_nitpick.marked[file.path] = true
    assert.same({ text = g.bubble .. " ", highlight = "ReviewCommentTreeIcon" }, g.gutter({}, file, {}))
  end)

  it("is always two cells wide while on", function()
    local g = reset()
    fake_triage.on = true
    fake_triage.by_path["/r/x"] = "approved"
    fake_nitpick.marked["/r/y"] = true
    for _, p in ipairs({ "/r/x", "/r/y", "/r/z" }) do
      assert.equals(2, vim.fn.strdisplaywidth(g.gutter({}, { type = "file", path = p }, {}).text), p)
    end
  end)
end)

describe("reviewgutter.icon", function()
  it("keeps neo-tree's padding while review mode is off", function()
    local g = reset()
    assert.same({ text = "I ", highlight = "NeoTreeFileIcon" }, g.icon({}, file, {}))
  end)

  it("drops the padding while review mode is on, so the gutter takes that cell", function()
    local g = reset()
    fake_triage.on = true
    assert.same({ text = "I", highlight = "NeoTreeFileIcon" }, g.icon({}, file, {}))
  end)
end)
