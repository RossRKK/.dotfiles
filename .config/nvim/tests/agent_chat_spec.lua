-- util/agent_chat.lua and plugins/codecompanion.lua against the real CodeCompanion
-- (lazy's install) and the claude-agent-acp home-manager puts on PATH.

local assert = require("luassert")

local lazy = vim.fn.stdpath("data") .. "/lazy/"
for _, dir in ipairs({ lazy .. "plenary.nvim", lazy .. "codecompanion.nvim" }) do
  vim.opt.runtimepath:prepend(dir)
end

require("codecompanion").setup(require("plugins.codecompanion")[1].opts)

--- The file a wrapper script's `--set-default NAME` points NAME at.
---@param script string
---@param name string
---@return string?
local function default_of(script, name)
  local text = table.concat(vim.fn.readfile(script), "\n")
  return text:match(name .. "=%${" .. name .. "%-'([^']+)'}")
end

describe("the Claude Code chat adapter", function()
  it("runs claude-agent-acp, which is on PATH", function()
    local adapter = require("codecompanion.adapters").resolve("claude_code")
    assert.equals("claude-agent-acp", adapter.commands.default[1])
    assert.equals(1, vim.fn.executable("claude-agent-acp"))
  end)

  it("drives the claude that loads the mods, so the agent view hears from it", function()
    local claude = default_of(vim.fn.exepath("claude-agent-acp"), "CLAUDE_CODE_EXECUTABLE")
    assert.is_not_nil(claude)
    local wrapper = table.concat(vim.fn.readfile(claude), "\n")
    assert.truthy(wrapper:find("%-%-plugin%-dir %S*/claude%-plugins/agent%-status"))
  end)
end)

describe("agent_chat", function()
  local helpers = require("codecompanion.interactions.chat.helpers")
  local real_connect, real_fishmonger

  before_each(function()
    -- No agent process: the chat would start one a tick after it is made.
    real_connect = helpers.create_acp_connection
    helpers.create_acp_connection = function(chat, cb) end ---@diagnostic disable-line: unused-local
    real_fishmonger = package.loaded["fishmonger"]
    vim.cmd("silent only!")
  end)

  after_each(function()
    helpers.create_acp_connection = real_connect
    package.loaded["fishmonger"] = real_fishmonger
  end)

  it("makes a chat buffer in no window", function()
    local buf = require("util.agent_chat").new()
    assert.is_not_nil(require("codecompanion").buf_get_chat(buf))
    assert.same({}, vim.fn.win_findbuf(buf))
  end)

  -- edgy docks the side panel by this filetype (plugins/edgy.lua).
  it(
    "keeps CodeCompanion on the window a host shows the chat in, as a codecompanion buffer",
    function()
      local buf = require("util.agent_chat").new()
      vim.cmd("vsplit")
      local win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(win, buf)
      assert.equals(win, require("codecompanion").buf_get_chat(buf).ui.winnr)
      assert.equals("codecompanion", vim.bo[buf].filetype)
    end
  )

  it("hands the chat to fishmonger's next free tab", function()
    local hosted
    package.loaded["fishmonger"] = {
      new = function(opts)
        hosted = opts.buf
        return true
      end,
    }
    require("util.agent_chat").open()
    assert.is_not_nil(require("codecompanion").buf_get_chat(hosted))
  end)

  it("drops the chat when every tab is taken", function()
    local offered
    package.loaded["fishmonger"] = {
      new = function(opts)
        offered = opts.buf
        return false
      end,
    }
    require("util.agent_chat").open()
    assert.is_false(vim.api.nvim_buf_is_valid(offered))
  end)
end)
