local assert = require("luassert")
local message_log = require("util.message_log")

local function echo(text)
  vim.api.nvim_echo({ { text } }, true, {})
end

local function read(path)
  local file = io.open(path)
  if not file then
    return ""
  end
  local text = file:read("*a")
  file:close()
  return text
end

local function entry(text)
  return "^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d %["
    .. vim.fn.getpid()
    .. "%] "
    .. vim.pesc(text)
    .. "\n"
end

describe("message_log", function()
  local path, log

  before_each(function()
    vim.cmd("messages clear")
    vim.o.messagesopt = "hit-enter,history:500"
    path = vim.fn.tempname() .. "/messages.log"
    log = message_log.new({ path = path, max_bytes = 1024 * 1024 })
  end)

  it("appends each history entry under a timestamp, multi-line text intact", function()
    echo("one")
    echo("traceback:\n\tframe a\n\tframe b")
    log:capture()

    local lines = read(path)
    assert.matches(entry("one"), lines)
    assert.matches(
      entry("traceback:\n\tframe a\n\tframe b"),
      lines:sub(#lines:match("^[^\n]*\n") + 1)
    )
  end)

  it("writes only the entries added since the last capture", function()
    echo("first")
    log:capture()
    log:capture()
    echo("second")
    log:capture()

    local _, firsts = read(path):gsub("first", "")
    assert.equals(1, firsts)
    assert.matches("first\n.*second\n$", read(path))
  end)

  it("logs a repeat of the last message again", function()
    echo("same")
    log:capture()
    echo("same")
    log:capture()

    local _, count = read(path):gsub("same", "")
    assert.equals(2, count)
  end)

  it("keeps up when the history drops its oldest entries", function()
    vim.o.messagesopt = "hit-enter,history:3"
    echo("a")
    echo("b")
    echo("c")
    log:capture()
    echo("d")
    echo("e")
    log:capture()

    local logged = vim.tbl_map(function(line)
      return line:match("%] (.*)$")
    end, vim.split(vim.trim(read(path)), "\n"))
    assert.same({ "a", "b", "c", "d", "e" }, logged)
  end)

  it("logs what follows a :messages clear", function()
    echo("before")
    log:capture()
    vim.cmd("messages clear")
    echo("after")
    log:capture()

    assert.matches("before\n.*after\n$", read(path))
  end)

  it("moves a full log aside to .1 and starts a fresh one", function()
    log = message_log.new({ path = path, max_bytes = 64 })
    echo(string.rep("x", 40))
    log:capture()
    echo("next")
    log:capture()

    assert.matches(string.rep("x", 40), read(path .. ".1"))
    assert.matches(entry("next") .. "$", read(path))
  end)

  it("captures on VimLeavePre once set up", function()
    message_log.setup({ path = path, max_bytes = 1024 * 1024, interval_ms = 60 * 60 * 1000 })
    echo("on exit")
    vim.api.nvim_exec_autocmds("VimLeavePre", {})

    assert.matches("on exit\n", read(path))
  end)
end)
