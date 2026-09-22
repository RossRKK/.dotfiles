-- util/reviewgutter: the shared review gutter is two cells wide (status, pad)
-- on every row while review mode is on, three on a commented row (status,
-- bubble, pad), and absent while it is off. A comment always comes with a
-- status, so only commented rows shift against their neighbours.

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
local blank, pad = { text = " " }, { text = " " }

local function width(chunks)
  local w = 0
  for _, c in ipairs(chunks) do
    w = w + vim.fn.strdisplaywidth(c.text)
  end
  return w
end

describe("reviewgutter.gutter", function()
  it("draws nothing while review mode is off, even for a marked file", function()
    local g = reset()
    fake_triage.by_path[file.path] = "approved"
    fake_nitpick.marked[file.path] = true
    assert.same({ text = "" }, g.gutter({}, file, {}))
  end)

  it("reserves two cells for an unmarked row while review mode is on", function()
    local g = reset()
    fake_triage.on = true
    assert.same({ blank, pad }, g.gutter({}, file, {}))
  end)

  it("draws the triage glyph in the first cell for a marked file", function()
    local g = reset()
    fake_triage.on = true
    fake_triage.by_path[file.path] = "approved"
    assert.same({ { text = "V", highlight = "ReviewApproved" }, pad }, g.gutter({}, file, {}))
  end)

  it("uses the rolled-up folder status for a directory", function()
    local g = reset()
    fake_triage.on = true
    fake_triage.by_dir[dir.path] = "approved"
    assert.same({ { text = "V", highlight = "ReviewApproved" }, pad }, g.gutter({}, dir, {}))
  end)

  it("adds the bubble between the status and the pad for a commented file", function()
    local g = reset()
    fake_triage.on = true
    fake_triage.by_path[file.path] = "approved"
    fake_nitpick.marked[file.path] = true
    assert.same({
      { text = "V", highlight = "ReviewApproved" },
      { text = g.bubble, highlight = "ReviewCommentTreeIcon" },
      pad,
    }, g.gutter({}, file, {}))
  end)

  it("is two cells wide on unmarked and status-only rows, three on commented rows", function()
    local g = reset()
    fake_triage.on = true
    fake_triage.by_path["/r/x"] = "approved"
    fake_triage.by_path["/r/w"] = "approved"
    fake_nitpick.marked["/r/w"] = true
    assert.equals(2, width(g.gutter({}, { type = "file", path = "/r/z" }, {})), "unmarked")
    assert.equals(2, width(g.gutter({}, { type = "file", path = "/r/x" }, {})), "status only")
    assert.equals(3, width(g.gutter({}, { type = "file", path = "/r/w" }, {})), "commented")
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
