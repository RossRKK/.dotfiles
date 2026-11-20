-- Agent chats are fishmonger tabs: each tab holds one agentic.nvim session, its
-- chat in the tab's window with the prompt and panels stacked under it, started
-- in the workspace's directory. The one place that knows both plugins.

local M = {}

local claude_session = require("util.claude_session")

---@class agent_chat.Options
---@field claude_sessions string Claude's live-session records (util/claude_session.lua)
---@field claude_projects string Claude's projects directory, holding each session's transcript
local options = {
  claude_sessions = vim.fn.expand("~/.claude/sessions"),
  claude_projects = vim.fn.expand("~/.claude/projects"),
}

---@param opts agent_chat.Options
function M.setup(opts)
  options = vim.tbl_extend("force", options, opts)
end

local host, host_first, newest, start_spec, paste, attach, paint, repaint_all, title_hl, set_title_hl -- defined below their callers

-- A session's name and colour arrive as agent-status and Claude report them.
vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("AgentChat", { clear = true }),
  pattern = "FishmongerAgentsChanged",
  callback = function()
    repaint_all()
  end,
})

-- <C-b>a: a new agent tab in the lowest free slot, its session started in the
-- directory fishmonger gives the tabpage rather than the focused window's.
function M.new(tab)
  local fishmonger = require("fishmonger")
  host(start_spec(fishmonger.dir(tab)), fishmonger.new)
end

--- Terminal 1's agent chat in `tab`: back in session `session_id` when given, else
--- in the directory's newest conversation, or a new one when it has none, as
--- `claude --continue; or claude` does for a terminal.
--- Its Claude is told it is terminal 1's (WORKSPACE_TERMINAL=1), so the
--- session-identity mod gives it a standing role or `agent_name`.
---@param tab integer
---@param session_id? string a session whose transcript exists
---@param agent_name? string
function M.start(tab, session_id, agent_name)
  local dir = require("fishmonger").dir(tab)
  local env = { WORKSPACE_TERMINAL = "1", CLAUDE_AGENT_NAME = agent_name }
  local function first(cwd, id)
    local spec = start_spec(cwd, id)
    -- Claude Agent ACP's per-session environment for that session's Claude.
    spec.meta = { claudeCode = { options = { env = env } } }
    host_first(tab, spec)
  end
  if session_id then
    return first(claude_session.cwd(options.claude_projects, session_id) or dir, session_id)
  end
  newest(dir, function(id)
    first(dir, id)
  end)
end

--- agentic's start spec: session `session_id` loaded, else a new one, in `cwd`.
---@param cwd string
---@param session_id? string
---@return agentic.SessionStartSpec
function start_spec(cwd, session_id)
  local function in_cwd()
    return cwd
  end
  if session_id then
    return { kind = "load", session_id = session_id, cwd = in_cwd }
  end
  return { kind = "new", cwd = in_cwd }
end

--- Host the session `spec` starts in slot 1 of `tab`, leaving focus where it is.
---@param tab integer
---@param spec agentic.SessionStartSpec
function host_first(tab, spec)
  local fishmonger = require("fishmonger")
  -- Finding the newest session takes a round trip, in which the tab may have closed or slot 1 filled.
  if
    not vim.api.nvim_tabpage_is_valid(tab)
    or vim.iter(fishmonger.tabs(tab)):any(function(term)
      return term.slot == 1
    end)
  then
    return
  end
  local focus = vim.api.nvim_get_current_win()
  host(spec, function(opts)
    fishmonger.show(1, vim.tbl_extend("force", opts, { tab = tab, insert = false }))
    return true
  end)
  if vim.api.nvim_win_is_valid(focus) then
    vim.api.nvim_set_current_win(focus)
  end
end

--- Calls `found` with the id of the newest session the provider lists for `dir`, or nil for none.
---@param dir string
---@param found fun(session_id: string?)
function newest(dir, found)
  local agent = require("agentic.acp.agent_instance").get_instance(require("agentic.config").provider)
  if not agent then
    return found(nil)
  end
  agent:when_ready(function()
    agent:list_sessions(dir, function(result)
      vim.schedule(function()
        local latest = result and result.sessions[1]
        found(latest and latest.sessionId)
      end)
    end)
  end, function()
    found(nil)
  end)
end

--- Start a session from `spec` and give its chat to fishmonger through `place`,
--- which takes fishmonger.show's hosting options and says whether it found a slot.
---@param spec agentic.SessionStartSpec
---@param place fun(opts: table): boolean
function host(spec, place)
  -- agentic's public new_session asks what to do with the current session and
  -- keeps the new one's key to itself; every agent tab keeps its own session.
  local registry = require("agentic.session_registry")
  local session = registry.create(nil, spec)
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

  -- Ctrl+N leaves insert mode in the prompt as it leaves terminal mode in a side terminal (config/keymaps.lua).
  vim.keymap.set("i", "<C-n>", "<Esc>", { buffer = session.widget.buf_nrs.input, desc = "Agent prompt: normal mode" })
  -- Replaces agentic's Ctrl+V to share the clipboard reads of every other Ctrl+V (config/keymaps.lua).
  vim.keymap.set("i", "<C-v>", function()
    paste(key, function(text)
      vim.api.nvim_paste(text, true, -1)
    end)
  end, { buffer = session.widget.buf_nrs.input, desc = "Agent prompt: paste text, or attach an image or file" })
  -- p/P from the clipboard paste as Ctrl+V does, text put natively; from any other register, as ever.
  for _, lhs in ipairs({ "p", "P" }) do
    vim.keymap.set("n", lhs, function()
      local put = ("normal! %d\"%s%s"):format(vim.v.count1, vim.v.register, lhs)
      if vim.v.register ~= "+" and vim.v.register ~= "*" then
        return vim.cmd(put)
      end
      paste(key, function()
        vim.cmd(put)
      end)
    end, { buffer = session.widget.buf_nrs.input, desc = "Agent prompt: put text, or attach an image or file" })
  end

  -- The tab is the session: killing it (<C-b>&, closing the workspace) ends it.
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = vim.schedule_wrap(function()
      registry.destroy(key)
    end),
  })

  local hosted = place({
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

--- Paste the clipboard into session `key`'s prompt: text goes in by `put_text`, unless it is only a
--- path to a file, which is attached, as are an image and files copied on Windows.
---@param key integer
---@param put_text fun(text: string)
function paste(key, put_text)
  local clipboard = require("util.clipboard")
  local text = clipboard.text()
  if text then
    local path = clipboard.path_in(text)
    if not (path and attach(key, { path })) then
      put_text(text)
    end
    return
  end
  clipboard.read_windows(function(content)
    if not content then
      vim.notify("Nothing to paste: the clipboard holds no text, image or file", vim.log.levels.INFO)
    elseif content.kind == "files" then
      attach(key, content.paths)
    else
      -- agentic attaches files, read when the prompt is sent; nvim's temp dir goes when it exits.
      local file = vim.fn.tempname() .. ".png"
      local out = assert(io.open(file, "wb"))
      out:write(content.png)
      out:close()
      attach(key, { file })
    end
  end)
end

--- Attach `paths` to session `key`'s next prompt, saying whether it took any.
---@param key integer
---@param paths string[]
---@return boolean
function attach(key, paths)
  local live = require("agentic.session_registry").get(key)
  local took = false
  for _, path in ipairs(paths) do
    took = (live and live.file_list:add(path)) or took
  end
  return took
end

--- The name the Claude behind ACP session `session_id` goes by, or nil before it has one.
---@param session_id string?
---@return string?
function M.agent_name(session_id)
  local record = session_id and require("fishmonger.agent").get(session_id)
  return record and claude_session.name(options.claude_sessions, record.agent_pid)
end

--- The prompt's title: the agent's name, so its identity sits by the prompt, then agentic's context and suffix.
---@param parts agentic.ui.ChatWidget.HeaderParts
---@param session_state agentic.acp.SessionState?
---@return string
function M.input_header(parts, session_state)
  local session = vim.iter(require("agentic.session_registry").list()):find(function(s)
    return s.session_state == session_state
  end)
  local pieces = {}
  -- "Prompt" rather than agentic's title, which leads with an icon glyph.
  for _, piece in ipairs({ session and M.agent_name(session.session_id) or false, "Prompt", parts.context or false, parts.suffix or false }) do
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
    or (record.transcript and claude_session.recorded_colours({ record.transcript })[record.transcript])
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
