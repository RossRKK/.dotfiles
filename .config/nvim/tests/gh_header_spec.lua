-- The header of snacks.nvim's gh:// buffers as util/gh_header reshapes it, on the real snacks.

local assert = require("luassert")
require("tests.helpers.plugins").add("snacks.nvim")
require("snacks")
local gh_header = require("util.gh_header")
local render = require("snacks.gh.render")

--- A copy of snacks' props, patched.
local function patched()
  local props = vim.list_extend({}, render.props)
  gh_header.patch(props)
  return props
end

--- A patched prop by name.
local function prop(name)
  return assert(vim.iter(patched()):find(function(p)
    return p.name == name
  end))
end

local opts = {
  icons = {
    checkmark = "C",
    crossmark = "X",
    merge_status = { clean = "c", dirty = "d", blocked = "b", unstable = "u" },
  },
}

--- A prop line's text, or nil for none.
local function line(p, item)
  local chunks = p.hl(item, opts)
  return chunks and table.concat(vim.tbl_map(function(c)
    return c[1]
  end, chunks))
end

describe("gh_header.patch", function()
  it("drops Repo and Changes and joins the times and the merge state, in snacks' order", function()
    assert.same(
      {
        "Status",
        "Author",
        "Opened",
        "Closed",
        "Merged",
        "Reactions",
        "Labels",
        "Assignees",
        "Milestone",
        "Merge",
        "Checks",
      },
      vim.tbl_map(function(p)
        return p.name
      end, patched())
    )
  end)

  it("fails loudly when a prop it reshapes is gone", function()
    local props = vim.tbl_filter(function(p)
      return p.name ~= "Changes"
    end, render.props)
    assert.has_error(function()
      gh_header.patch(props)
    end, 'snacks gh header: no "Changes" prop to patch')
  end)

  it("says when the PR was opened and last updated, in snacks' relative time", function()
    local opened = prop("Opened")
    local now = os.time()
    assert.equals(
      "3 days ago · updated 2 hours ago",
      line(opened, { created = now - 3 * 86400, updated = now - 7200 })
    )
    assert.equals("3 days ago", line(opened, { created = now - 3 * 86400 }))
  end)

  it("joins whether the PR is mergeable with its merge status, either alone, or neither", function()
    local merge = prop("Merge")
    local status = { mergeStateStatus = "BLOCKED", state = "open" }
    assert.equals(
      "C · b Blocked",
      line(merge, vim.tbl_extend("force", status, { mergeable = true }))
    )
    assert.equals("b Blocked", line(merge, status))
    assert.equals("C", line(merge, { mergeable = true, state = "merged" }))
    assert.is_nil(line(merge, { state = "merged" }))
  end)
end)
