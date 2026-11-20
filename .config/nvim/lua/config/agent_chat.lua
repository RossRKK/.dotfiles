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

local paint, repaint_all, title_hl, set_title_hl -- defined below their callers

-- A session's name and colour arrive as agent-status and Claude report them.
vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("AgentChat", { clear = true }),
  pattern = "FishmongerAgentsChanged",
  callback = function()
    repaint_all()
  end,
})

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

  -- agentic opens its panels' windows afresh on each show; each new one is painted once agentic has set it up.
  for name, panel in pairs(session.widget.buf_nrs) do
    if name ~= "chat" then
      vim.api.nvim_create_autocmd("BufWinEnter", {
        buffer = panel,
        callback = vim.schedule_wrap(function()
          local live = registry.get(key)
          if live then
            paint(live)
          end
        end),
      })
    end
  end

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

--- The prompt's title: the agent's name, so its identity sits by the prompt, then agentic's parts.
---@param parts agentic.ui.ChatWidget.HeaderParts
---@param session_state agentic.acp.SessionState?
---@return string
function M.input_header(parts, session_state)
  local session = vim.iter(require("agentic.session_registry").list()):find(function(s)
    return s.session_state == session_state
  end)
  local pieces = {}
  for _, piece in ipairs({ session and M.agent_name(session.session_id) or false, parts.title, parts.context or false, parts.suffix or false }) do
    if piece then
      pieces[#pieces + 1] = piece
    end
  end
  return table.concat(pieces, " | ")
end

--- The /color of the Claude behind ACP session `session_id`: its claim, else the last
--- /color its transcript records, which is all a /color typed by hand updates.
---@param session_id string?
---@return string?
function M.agent_colour(session_id)
  local record = session_id and require("fishmonger.agent").get(session_id)
  if not record then
    return nil
  end
  return record.colour
    or (record.transcript and require("util.worktree").recorded_colours({ record.transcript })[record.transcript])
end

-- Every session's titles, for when names or colours may have changed.
function repaint_all()
  for _, session in ipairs(require("agentic.session_registry").list()) do
    paint(session)
    session.widget:render_header("input")
  end
end

-- Paints a session's panel titles in its colour. Not the chat's window: that is
-- fishmonger's, titled by its tab strip.
function paint(session)
  local hl = title_hl(M.agent_colour(session.session_id))
  for name, win in pairs(session.widget.win_nrs) do
    if name ~= "chat" and vim.api.nvim_win_is_valid(win) then
      set_title_hl(win, hl)
    end
  end
end

--- The title group for a /color, or nil for none fishmonger knows.
---@param colour string?
---@return string?
function title_hl(colour)
  local hex = require("fishmonger.agent").colours[colour]
  if not hex then
    return nil
  end
  local name = "AgentChatTitle" .. colour:gsub("^%l", string.upper)
  -- Set on every paint so a colorscheme's :hi clear can't leave it undefined.
  vim.api.nvim_set_hl(0, name, { bg = hex, fg = "#000000", bold = true })
  return name
end

-- agentic draws its titles in AgenticTitle; remapping it in 'winhighlight' keeps
-- agentic's own entries, where a window highlight namespace would replace them.
function set_title_hl(win, hl)
  local kept = vim.tbl_filter(function(entry)
    return not vim.startswith(entry, "AgenticTitle:")
  end, vim.split(vim.wo[win].winhighlight, ",", { trimempty = true }))
  if hl then
    kept[#kept + 1] = "AgenticTitle:" .. hl
  end
  vim.api.nvim_set_option_value("winhighlight", table.concat(kept, ","), { scope = "local", win = win })
end

return M
