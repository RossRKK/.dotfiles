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

local host, host_first, newest, start_spec, stop, paste, attach, type_into, pass_ctrl_keys, route_ctrl_key, chat_record, paint, repaint_all, title_hl, set_title_hl -- defined below their callers

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

  pass_ctrl_keys(session.widget.buf_nrs.input)

  -- Ctrl+C stops what this chat has running, as in Claude Code: its reply, then the sub-agents left running.
  for _, panel in pairs(session.widget.buf_nrs) do
    vim.keymap.set({ "n", "i" }, "<C-c>", function()
      stop(key)
    end, { buffer = panel, desc = "Agent chat: stop the agent's reply, else its running sub-agents" })
  end

  -- The tab is the session: killing it (<C-b>&, closing the workspace) ends it. Its events
  -- stop at once, so what the agent already sent never reaches the wiped buffers; the
  -- teardown waits a tick, as it shows other buffers in windows, which a wipe in progress refuses.
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      local live = registry.get(key)
      if live and live.session_id then
        live.agent:cancel_session(live.session_id)
      end
      vim.schedule(function()
        registry.destroy(key)
      end)
    end,
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
    -- The prompt and panels agentic split around the chat, so fishmonger treats them as the tab's own.
    windows = function()
      local live = registry.get(key)
      local wins = {}
      for name, win in pairs(live and live.widget.win_nrs or {}) do
        if name ~= "chat" then
          wins[#wins + 1] = win
        end
      end
      return wins
    end,
    -- Claude's session now, which /clear moves on from the ACP session's.
    session = function()
      local live = registry.get(key)
      local record = live and chat_record(live.session_id)
      return record and record.session
    end,
    -- Until its Claude has a name the tab still says what it is, not agentic's buffer name.
    title = function()
      local live = registry.get(key)
      return live and M.agent_name(live.session_id) or "agent"
    end,
    -- fishmonger.send (<leader>ya) types into the prompt, agentic's own buffer under the chat.
    send = function(text)
      local live = registry.get(key)
      local win = live and live.widget.win_nrs.input
      if win and vim.api.nvim_win_is_valid(win) then
        type_into(win, text)
      end
    end,
  })
  if not hosted then
    registry.destroy(key)
  end
end

--- Append `text` to the end of the prompt in `win` and type on from there.
---@param win integer
---@param text string
function type_into(win, text)
  local buf = vim.api.nvim_win_get_buf(win)
  local row = vim.api.nvim_buf_line_count(buf) - 1
  local col = #vim.api.nvim_buf_get_lines(buf, row, row + 1, true)[1]
  local lines = vim.split(text, "\n", { plain = true })
  vim.api.nvim_buf_set_text(buf, row, col, row, col, lines)
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_win_set_cursor(win, { row + #lines, 0 })
  vim.cmd("startinsert!")
end

--- Stop session `key`'s reply while it generates, else its running sub-agents; agentic stops nothing that isn't running.
---@param key integer
function stop(key)
  local live = require("agentic.session_registry").get(key)
  if not live then
    return
  end
  local agentic = require("agentic")
  if live.is_generating then
    agentic.stop_generation({ session = key })
  else
    agentic.stop_subagents({ session = key })
  end
end

--- Paste the clipboard into session `key`'s prompt: text goes in by `put_text`, unless it is only a
--- path to a file, which is attached, as are a copied image and copied files.
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
  clipboard.read(function(content)
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

-- Insert's own Ctrl keys that edit the prompt, not type into it; a normal mapping still wins.
local editing_ctrl_keys = {
  ["<C-g>"] = true,
  ["<C-h>"] = true,
  ["<C-j>"] = true,
  ["<C-o>"] = true,
  ["<C-r>"] = true,
  ["<C-u>"] = true,
  ["<C-w>"] = true,
}

--- Every Ctrl+letter insert mode in `buf` doesn't map goes through `route_ctrl_key`, so none
--- types a control character or a completion into the prompt. <C-i> and <C-m> are Tab and Enter.
---@param buf integer
function pass_ctrl_keys(buf)
  for letter in ("abcdefghjklnopqrstuvwxyz"):gmatch(".") do
    local lhs = "<C-" .. letter .. ">"
    local mapped = vim.api.nvim_buf_call(buf, function()
      return vim.fn.maparg(lhs, "i") ~= ""
    end)
    if not mapped then
      vim.keymap.set("i", lhs, function()
        return route_ctrl_key(lhs)
      end, {
        buffer = buf,
        expr = true,
        remap = true,
        desc = "Agent prompt: the key's normal-mode mapping, else nothing",
      })
    end
  end
end

--- What Ctrl key `lhs` does in the prompt: its normal-mode mapping, as from a side terminal;
--- else insert's own meaning in the completion menu or for a key that edits; else nothing.
---@param lhs string
---@return string
function route_ctrl_key(lhs)
  if vim.fn.maparg(lhs, "n") ~= "" then
    return "<C-\\><C-n>" .. lhs
  end
  -- Keys that start with the mapping's own lhs run the builtin, not the mapping again.
  if vim.fn.pumvisible() == 1 or editing_ctrl_keys[lhs] then
    return lhs
  end
  return ""
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
  local record = chat_record(session_id)
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
  local record = chat_record(session_id)
  if not record then
    return nil
  end
  return record.colour
    or (record.transcript and claude_session.recorded_colours({ record.transcript })[record.transcript])
end

--- The status record of the Claude behind ACP session `session_id`, or nil: the one naming
--- it as its chat's session, as Claude's own session id changes on /clear.
---@param session_id string?
---@return table?
function chat_record(session_id)
  return session_id
    and vim.iter(require("fishmonger.agent").all()):find(function(record)
      return record.chat_session == session_id
    end)
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
  -- A tint of the colour, as tokyonight tints its own bars: a full-width bar at full strength glares.
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local tint = require("tokyonight.util").blend(hex, 0.35, normal.bg and ("#%06x"):format(normal.bg) or "#000000")
  -- Set on every paint so a colorscheme's :hi clear can't leave it undefined.
  vim.api.nvim_set_hl(0, name, { bg = tint, fg = normal.fg or "#ffffff", bold = true })
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
