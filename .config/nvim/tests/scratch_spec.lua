-- Where the scratch pad lands on disk (util/scratch.lua). The path is the whole
-- contract with the shell -- it's what you type to pipe the file -- so the
-- naming is pinned here; opening the buffer needs a live window and isn't.

local assert = require("luassert")
local scratch = require("util.scratch")

describe("scratch.dir", function()
  local tmpdir = vim.env.TMPDIR

  after_each(function()
    vim.env.TMPDIR = tmpdir
  end)

  it("sits under $TMPDIR, the name the shell knows too", function()
    vim.env.TMPDIR = "/var/tmp/mine"
    assert.equals("/var/tmp/mine/nvim-scratch", scratch.dir())
  end)

  it("falls back to /tmp when TMPDIR is unset or empty", function()
    vim.env.TMPDIR = nil
    assert.equals("/tmp/nvim-scratch", scratch.dir())
    vim.env.TMPDIR = ""
    assert.equals("/tmp/nvim-scratch", scratch.dir())
  end)

  it("normalises a trailing slash away", function()
    vim.env.TMPDIR = "/var/tmp/mine/"
    assert.equals("/var/tmp/mine/nvim-scratch", scratch.dir())
  end)
end)

describe("scratch.filename", function()
  it("names the file after the workspace", function()
    assert.equals("ionics.md", scratch.filename("ionics"))
    assert.equals("my-repo_2.md", scratch.filename("my-repo_2"))
  end)

  it("keeps the name typeable in a shell", function()
    assert.equals("my-project.md", scratch.filename("my project"))
  end)

  it("leaves no way out of the scratch directory", function()
    assert.equals("scratch.md", scratch.filename(".."))
    assert.equals("a-b.md", scratch.filename("a/b"))
  end)

  it("falls back for a name with nothing filename-ish in it", function()
    assert.equals("scratch.md", scratch.filename(""))
    assert.equals("scratch.md", scratch.filename("..."))
  end)
end)
