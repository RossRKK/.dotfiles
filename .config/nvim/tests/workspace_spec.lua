-- config.workspace's naming: the jj side of display_name. vcsline and
-- jjworkspace are stubbed so no repo is needed; the git side reads the
-- greeter's report and is exercised through greeter_spec.

local assert = require("luassert")

describe("workspace.jj_name", function()
  local ws, info

  before_each(function()
    info = nil
    package.loaded["util.vcsline"] = {
      root_of = function(dir)
        return dir:match("^(.*/ionics/%.worktrees/[^/]+)") or dir:match("^(.*/ionics)")
      end,
      info_for = function()
        return info
      end,
      format = function(i, short)
        return short and i.bookmark or (i.bookmark .. " " .. i.change_id)
      end,
    }
    package.loaded["util.jjworkspace"] = {
      root = function()
        return "/home/me/dev/ionics"
      end,
    }
    package.loaded["config.workspace"] = nil
    ws = require("config.workspace")
  end)

  after_each(function()
    package.loaded["util.vcsline"] = nil
    package.loaded["util.jjworkspace"] = nil
    package.loaded["config.workspace"] = nil
  end)

  it("is the repo and the short statusline fragment", function()
    info = { bookmark = "main+1", change_id = "unlqxzkz" }
    assert.equals("ionics - main+1", ws.jj_name("/home/me/dev/ionics/src"))
  end)

  it("names a secondary workspace after the main repo, not its directory", function()
    info = { bookmark = "dd-x+2", change_id = "mxnuyzlm" }
    assert.equals("ionics - dd-x+2", ws.jj_name("/home/me/dev/ionics/.worktrees/dd-x"))
  end)

  it("is the bare repo before vcsline has answered", function()
    assert.equals("ionics", ws.jj_name("/home/me/dev/ionics"))
  end)

  it("is nil outside a jj repo", function()
    assert.is_nil(ws.jj_name("/home/me/other"))
  end)
end)
