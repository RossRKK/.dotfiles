-- Run inside the child nvim agent_close_spec starts with the full config: opens
-- an agent chat in a second tab against tests/helpers/fake_acp_agent.py, hands
-- agentic's client an update from the agent and closes the tab in the same
-- tick, then reports what happened as JSON to $PROBE_OUT and quits.

local function report()
  local provider = require("agentic.config").acp_providers["claude-agent-acp"]
  provider.command, provider.args = "python3", { vim.env.FAKE_AGENT }

  vim.cmd("tabnew")
  require("config.agent_chat").new(vim.api.nvim_get_current_tabpage())
  local registry = require("agentic.session_registry")
  local opened = vim.wait(10000, function()
    local session = registry.list()[1]
    return session ~= nil and session.session_id ~= nil
  end, 20)
  if not opened then
    return { error = "the chat never got a session" }
  end

  local session = registry.list()[1]
  vim.v.errmsg = ""
  -- An update the agent sent just before the tab closed, still in agentic's queue when it does.
  session.agent:_handle_notification(nil, "session/update", {
    sessionId = session.session_id,
    update = { sessionUpdate = "tool_call", toolCallId = "t1", title = "Read a file", kind = "read", status = "pending" },
  })
  vim.cmd("tabclose")
  -- Queued behind everything the close and the update queued, so it runs once they have.
  local drained = false
  vim.schedule(function()
    vim.schedule(function()
      drained = true
    end)
  end)
  vim.wait(5000, function()
    return drained
  end, 10)
  return { errmsg = vim.v.errmsg, sessions = #registry.list() }
end

-- After startup's own loads (lazy's VeryLazy never fires headless).
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = vim.schedule_wrap(function()
    local ok, result = pcall(report)
    vim.fn.writefile({ vim.json.encode(ok and result or { error = result }) }, vim.env.PROBE_OUT)
    vim.cmd("qa!")
  end),
})
