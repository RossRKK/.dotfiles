-- The pure half of util/vcsline.lua: turning `jj log` lines into the statusline
-- fragment, and picking the diff dict. The jj call itself is left to the real
-- thing.

local assert = require("luassert")
local vl = require("util.vcsline")

describe("vcsline.parse + format", function()
  local function render(out)
    local info = vl.parse(out)
    return info and vl.format(info)
  end

  -- jj prints newest first: @ at the top, the bookmark at the bottom.
  it("shows the bookmark, the distance to it and the change id", function()
    assert.equals("main+2 umzvrvxs", render("@\tumzvrvxs\t\n\tquxqtyqs\t\n\tabcdefgh\tmain\n"))
  end)

  it("does not depend on the line order", function()
    assert.equals("main+2 umzvrvxs", render("\tabcdefgh\tmain\n\tquxqtyqs\t\n@\tumzvrvxs\t\n"))
  end)

  it("drops the distance when the bookmark sits on @", function()
    assert.equals("main umzvrvxs", render("@\tumzvrvxs\tmain\n"))
  end)

  it("falls back to the bare change id with no bookmarked ancestor", function()
    assert.equals("umzvrvxs", render("@\tumzvrvxs\t\n"))
  end)

  it("takes the first of several bookmarks on one commit", function()
    assert.equals("main+1 umzvrvxs", render("\tabcdefgh\tmain,feature\n@\tumzvrvxs\t\n"))
  end)

  it("drops the change id in the short form, unless it is all there is", function()
    assert.equals("main+2", vl.format(vl.parse("@\tumzvrvxs\t\n\tquxqtyqs\t\n\tabcdefgh\tmain\n"), true))
    assert.equals("main", vl.format(vl.parse("@\tumzvrvxs\tmain\n"), true))
    assert.equals("umzvrvxs", vl.format(vl.parse("@\tumzvrvxs\t\n"), true))
  end)

  it("reads the workspace name off @'s line, first of several", function()
    assert.equals("default", vl.parse("@\tumzvrvxs\t\tdefault\n\tabcdefgh\tmain\t\n").workspace)
    assert.equals("agent", vl.parse("@\tumzvrvxs\tmain\tagent,default\n").workspace)
    assert.is_nil(vl.parse("@\tumzvrvxs\tmain\t\n").workspace)
  end)

  it("keeps the first bookmarked head when two lines merge into @", function()
    assert.equals(
      "a+2 umzvrvxs",
      render("\taaaaaaaa\ta\n\tbbbbbbbb\tb\n\tcccccccc\t\n@\tumzvrvxs\t\n")
    )
  end)

  it("has nothing to say about empty or foreign output", function()
    assert.is_nil(vl.parse(""))
    assert.is_nil(vl.parse("Error: no jj repo\n"))
  end)
end)

describe("vcsline.diff_source", function()
  before_each(function()
    vim.cmd("enew!")
  end)
  after_each(function()
    vim.cmd("bwipeout!")
  end)

  it("reads jjsigns' dict when gitsigns has none, renaming changed", function()
    vim.b.jjsigns_status_dict = { added = 1, changed = 2, removed = 3 }
    assert.same({ added = 1, modified = 2, removed = 3 }, vl.diff_source())
  end)

  it("prefers gitsigns' dict where both exist", function()
    vim.b.gitsigns_status_dict = { added = 5, changed = 0, removed = 0 }
    vim.b.jjsigns_status_dict = { added = 1, changed = 2, removed = 3 }
    assert.equals(5, vl.diff_source().added)
  end)

  it("is nil with no gutter attached", function()
    assert.is_nil(vl.diff_source())
  end)
end)
