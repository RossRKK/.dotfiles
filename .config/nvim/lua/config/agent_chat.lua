-- Agent chats are fishmonger tabs: each tab holds one agentic.nvim session, its
-- chat in the tab's window with the prompt and panels stacked under it, started
-- in the workspace's directory. The one place that knows both plugins.

local M = {}

local claude_session = require("util.claude_session")

---@class agent_chat.Options
---@field claude_sessions string Claude's live-session records (util/claude_session.lua)
local options = {
  claude_sessions = vim.fn.expand("~/.claude/sessions"),
}

---@param opts agent_chat.Options
function M.setup(opts)
  options = vim.tbl_extend("force", options, opts)
end

-- <C-b>A: a new agent tab in the lowest free slot, its session started in the
-- directory fishmonger gives the tabpage rather than the focused window's.
function M.new(tab)
  local fishmonger = require("fishmonger")
  -- agentic's public new_session asks what to do with the current session and
  -- keeps the new one's key to itself; every agent tab keeps its own session.
  local registry = require("agentic.session_registry")
  local dir = fishmonger.dir(tab)
  local session = registry.create(nil, {
    kind = "new",
    cwd = function()
      return dir
    end,
  })
  if not session then
    return
  end
  local key = session.session_key
  local buf = session.widget.buf_nrs.chat

  -- The tab is the session: killing it (<C-b>&, closing the workspace) ends it.
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = vim.schedule_wrap(function()
      registry.destroy(key)
    end),
  })

  local hosted = fishmonger.new({
    buf = buf,
    on_show = function(win)
      registry.show_session(key, { win = win })
    end,
    on_hide = function()
      local live = registry.get(key)
      if live then
        live.widget:hide()
      end
    end,
    -- The ACP session is Claude's own, so its id is the one agent-status reports under.
    session = function()
      local live = registry.get(key)
      return live and live.session_id
    end,
    -- Until its Claude has a name the tab still says what it is, not agentic's buffer name.
    title = function()
      local live = registry.get(key)
      return live and M.agent_name(live.session_id) or "agent"
    end,
  })
  if not hosted then
    registry.destroy(key)
  end
end

--- The name the Claude behind ACP session `session_id` goes by, or nil before it has one.
---@param session_id string?
---@return string?
function M.agent_name(session_id)
  local record = session_id and require("fishmonger.agent").get(session_id)
  return record and claude_session.name(options.claude_sessions, record.agent_pid)
end

return M
