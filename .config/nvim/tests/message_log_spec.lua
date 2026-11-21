local assert = require("luassert")
local message_log = require("util.message_log")

local function read(path)
  local file = assert(io.open(path))
  local text = file:read("*a")
  file:close()
  return text
end

local function touch(path)
  assert(io.open(path, "w")):close()
end

describe("message_log.setup", function()
  local dir

  before_each(function()
    dir = vim.fn.tempname()
  end)

  after_each(function()
    vim.o.verbosefile = ""
  end)

  it("sends this nvim's messages to a log named by its start time and pid", function()
    message_log.setup({ dir = dir, keep_previous = 20 })
    local path = vim.o.verbosefile
    vim.api.nvim_echo({ { "traceback:\n\tframe a" } }, true, {})
    vim.o.verbosefile = ""

    assert.matches(
      "^"
        .. vim.pesc(dir)
        .. "/messages%-%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d%-"
        .. vim.fn.getpid()
        .. "%.log$",
      path
    )
    assert.matches("traceback:\n\tframe a", read(path))
  end)

  it("deletes all but the newest previous logs, leaving other files alone", function()
    vim.fn.mkdir(dir, "p")
    for _, name in ipairs({
      "messages-20261101-090000-11.log",
      "messages-20261102-090000-12.log",
      "messages-20261103-090000-13.log",
      "nvim.log",
    }) do
      touch(dir .. "/" .. name)
    end

    message_log.setup({ dir = dir, keep_previous = 2 })

    local names = vim.fn.readdir(dir)
    table.sort(names)
    assert.same({
      "messages-20261102-090000-12.log",
      "messages-20261103-090000-13.log",
      vim.fs.basename(vim.o.verbosefile),
      "nvim.log",
    }, names)
  end)
end)
