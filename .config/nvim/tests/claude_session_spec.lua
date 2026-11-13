-- util.claude_session: the name a live Claude goes by, from Claude Code's session record.

local assert = require("luassert")
local claude_session = require("util.claude_session")

describe("claude_session.name", function()
  local dir

  local function record(pid, text)
    vim.fn.writefile({ text }, dir .. "/" .. pid .. ".json")
  end

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
  end)

  after_each(function()
    vim.fn.delete(dir, "rf")
  end)

  it("reads the name the session goes by", function()
    record(7, vim.json.encode({ pid = 7, name = "dotty", nameSource = "user" }))
    assert.equals("dotty", claude_session.name(dir, 7))
  end)

  it("has none for a process with no record", function()
    assert.is_nil(claude_session.name(dir, 8))
  end)

  it("has none for a record caught mid-write", function()
    record(9, '{"pid":9,"name":"dot')
    assert.is_nil(claude_session.name(dir, 9))
  end)

  it("has none for a session not named yet", function()
    record(10, vim.json.encode({ pid = 10, name = vim.NIL }))
    assert.is_nil(claude_session.name(dir, 10))
  end)
end)

describe("claude_session.role", function()
  local home, roles, real_home

  before_each(function()
    home = vim.uv.fs_realpath(vim.fn.tempname()) or vim.fn.tempname()
    vim.fn.mkdir(home .. "/.dotfiles", "p")
    vim.fn.mkdir(home .. "/widget", "p")
    roles = home .. "/claude-roles"
    real_home = vim.env.HOME
    vim.env.HOME = home
  end)

  after_each(function()
    vim.env.HOME = real_home
    vim.fn.delete(home, "rf")
  end)

  it("gives a checkout listed under ~ its role", function()
    vim.fn.writefile({ "~/widget captain", "~/.dotfiles dotty" }, roles)
    assert.equals("dotty", claude_session.role(roles, home .. "/.dotfiles"))
  end)

  it("gives a checkout no role when it isn't listed", function()
    vim.fn.writefile({ "~/.dotfiles dotty" }, roles)
    assert.is_nil(claude_session.role(roles, home .. "/widget"))
  end)

  it("gives no role without a roles file", function()
    assert.is_nil(claude_session.role(roles, home .. "/.dotfiles"))
  end)
end)
