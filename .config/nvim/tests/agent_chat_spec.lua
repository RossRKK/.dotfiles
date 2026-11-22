-- config.agent_chat: an agent chat is a fishmonger tab. Runs the real
-- fishmonger (its shells faked, as in its own suite) against a fake
-- agentic session registry that records what the glue asks of it.

local assert = require("luassert")

-- The title tint blends with tokyonight's own helper.
vim.opt.runtimepath:prepend(vim.fn.stdpath("data") .. "/lazy/tokyonight.nvim")

local agent_chat, fishmonger
local created, shown, hidden, destroyed, rendered, stopped

--- A fake agentic session whose chat buffer has agentic's filetype, its prompt
--- opened under the chat on show as agentic's is.
local function fake_session(key)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "AgenticChat"
  local widget
  widget = {
    buf_nrs = { chat = buf, input = vim.api.nvim_create_buf(false, true), todos = vim.api.nvim_create_buf(false, true) },
    win_nrs = {},
    hide = function()
      hidden[#hidden + 1] = key
      if widget.win_nrs.input and vim.api.nvim_win_is_valid(widget.win_nrs.input) then
        vim.api.nvim_win_close(widget.win_nrs.input, true)
      end
      widget.win_nrs = {}
    end,
    render_header = function(_, window_name)
      rendered[#rendered + 1] = { key = key, window = window_name }
    end,
  }
  -- As agentic's: takes a path only to a file that exists.
  local file_list = { files = {} }
  function file_list:add(path)
    local stat = vim.uv.fs_stat(path)
    if stat and stat.type == "file" then
      self.files[#self.files + 1] = path
      return true
    end
    return false
  end
  local session = { session_key = key, session_id = "acp-" .. key, session_state = {}, widget = widget, file_list = file_list }
  session.is_generating = false
  return session
end

--- agentic's two stops, recording which one is asked of which session.
local function fake_agentic()
  return {
    stop_generation = function(opts)
      stopped[#stopped + 1] = { "reply", opts.session }
    end,
    stop_subagents = function(opts)
      stopped[#stopped + 1] = { "subagents", opts.session }
    end,
  }
end

local function fake_registry()
  local sessions = {}
  return {
    create = function(provider, spec) ---@diagnostic disable-line: unused-local
      local session = fake_session(#created + 1)
      created[#created + 1] = {
        session = session,
        kind = spec.kind,
        session_id = spec.session_id,
        cwd = spec.cwd(vim.fn.getcwd()),
        meta = spec.meta,
      }
      sessions[session.session_key] = session
      return session
    end,
    show_session = function(key, opts)
      shown[#shown + 1] = { key = key, win = opts.win }
      local widget = sessions[key].widget
      widget.win_nrs.chat = opts.win
      widget.win_nrs.input = vim.api.nvim_open_win(widget.buf_nrs.input, false, { split = "below", win = opts.win })
      vim.wo[widget.win_nrs.input].winhighlight = "EndOfBuffer:"
    end,
    list = function()
      return vim.tbl_values(sessions)
    end,
    get = function(key)
      return sessions[key]
    end,
    destroy = function(key)
      local session = sessions[key]
      if not session then
        return -- as agentic's: an unknown key is a no-op
      end
      destroyed[#destroyed + 1] = key
      sessions[key] = nil
      if vim.api.nvim_buf_is_valid(session.widget.buf_nrs.chat) then
        vim.api.nvim_buf_delete(session.widget.buf_nrs.chat, { force = true })
      end
    end,
  }
end

local jobstart = vim.fn.jobstart

--- A fresh real fishmonger, its shells faked, and agent_chat over the fake registry.
local function fresh()
  pcall(vim.cmd, "tabonly!")
  pcall(vim.cmd, "only!")
  vim.w.fishmonger_side = nil
  created, shown, hidden, destroyed, rendered, stopped = {}, {}, {}, {}, {}, {}
  -- Keep jobstart's real arity, as fishmonger's own suite does.
  vim.fn.jobstart = function(cmd, opts) ---@diagnostic disable-line: duplicate-set-field, unused-local
    return 1
  end
  package.loaded["fishmonger"] = nil
  fishmonger = require("fishmonger")
  fishmonger.setup_exit()
  package.loaded["agentic.session_registry"] = fake_registry()
  package.loaded["agentic"] = fake_agentic()
  package.loaded["config.agent_chat"] = nil
  agent_chat = require("config.agent_chat")
end

local function unfake()
  vim.fn.jobstart = jobstart
  package.loaded["agentic.session_registry"] = nil
  package.loaded["agentic"] = nil
  package.loaded["fishmonger"] = nil
end

describe("agent_chat.new", function()
  before_each(fresh)
  after_each(unfake)

  local function new()
    agent_chat.new(vim.api.nvim_get_current_tabpage())
  end

  it("opens a new agent tab in the panel and shows its session there", function()
    new()

    assert.equals(1, #created)
    local chat = created[1].session.widget.buf_nrs.chat
    assert.equals(chat, vim.api.nvim_win_get_buf(fishmonger.win))
    assert.same({ { key = 1, win = fishmonger.win } }, shown)
  end)

  it("starts the session in the tabpage's directory, not the focused window's", function()
    local root = vim.fn.getcwd()
    vim.cmd("tabnew")
    vim.cmd.tcd(vim.fn.fnameescape(vim.fn.fnamemodify(vim.fn.tempname(), ":h")))
    local tab_dir = vim.fn.getcwd()
    vim.cmd.lcd(vim.fn.fnameescape(root))

    new()

    assert.are_not.equal(root, tab_dir)
    assert.equals(tab_dir, created[1].cwd)
  end)

  it("makes another agent tab each time, hiding the one it replaces", function()
    new()
    new()

    assert.equals(2, #created)
    assert.equals(2, fishmonger.current)
    assert.same({ 1 }, hidden)
  end)

  it("hides the session when the panel closes", function()
    new()
    fishmonger.toggle()

    assert.is_false(fishmonger.panel_open())
    assert.same({ 1 }, hidden)
  end)

  it("ends the session when its tab is killed", function()
    new()
    fishmonger.kill()
    -- Scheduled out of BufWipeout; waits on the outcome, not a duration.
    vim.wait(1000, function()
      return #destroyed > 0
    end)

    assert.same({ 1 }, destroyed)
  end)

  it("ends the session it made when every slot is taken", function()
    for slot = 1, 9 do
      fishmonger.show(slot)
    end
    local notify = vim.notify
    vim.notify = function(msg, level, opts) end ---@diagnostic disable-line: duplicate-set-field, unused-local
    new()
    vim.notify = notify

    assert.same({ 1 }, destroyed)
  end)

  describe("its tab", function()
    local root

    before_each(function()
      root = vim.fn.tempname()
      vim.fn.mkdir(root .. "/agents", "p")
      vim.fn.mkdir(root .. "/sessions", "p")
      fishmonger.setup({ agent = { dir = root .. "/agents" } })
      -- refresh_agents is the only repaint here: the watcher's would race the assertions.
      require("fishmonger.agent")._watcher:stop()
      agent_chat.setup({ claude_sessions = root .. "/sessions" })
    end)

    --- Report ACP session `id` as agent-status and Claude would: its status, and its name.
    ---@param fields? table more of the status record
    local function report(id, name, fields)
      local pid = vim.fn.getpid() -- alive, so the record survives the liveness check
      local record = vim.tbl_extend("force", { session = id, state = "done", agent_pid = pid, pids = { pid } }, fields or {})
      vim.fn.writefile({ vim.json.encode(record) }, root .. "/agents/" .. id .. ".json")
      vim.fn.writefile({ vim.json.encode({ pid = pid, name = name }) }, root .. "/sessions/" .. pid .. ".json")
      require("fishmonger").refresh_agents()
    end

    --- Claim `colour` for this nvim's pid, as the session-identity mod does for its Claude.
    local function claim(colour)
      local pid = vim.fn.getpid()
      local stat = assert(io.open("/proc/" .. pid .. "/stat")):read("*a")
      local pid_start = tonumber(vim.split(stat:match(".*%) (.*)"), " ")[20])
      vim.fn.writefile({ vim.json.encode({ colour = colour, pid_start = pid_start }) }, root .. "/agents/" .. pid .. ".colour")
    end

    local function prompt_winhighlight()
      return vim.wo[created[1].session.widget.win_nrs.input].winhighlight
    end

    local function strip()
      vim.g.statusline_winid = fishmonger.win
      local out = fishmonger.winbar()
      vim.g.statusline_winid = nil
      return (out:gsub("%%%d+@[^@]*@", ""):gsub("%%#[^#]*#", ""):gsub("%%X", ""))
    end

    it("shows its session's status icon, then its Claude's name", function()
      new()
      report("acp-1", "calm-otter")

      local done = require("fishmonger.agent").states.done.icon
      assert.equals(" 1:" .. require("fishmonger.agent").glyph_cell(done) .. "calm-otter ", strip())
    end)

    it("says agent until its Claude has a name", function()
      new()

      assert.equals(" 1:agent ", strip())
    end)

    it("paints its prompt's title in its session's colour, keeping agentic's highlights", function()
      new()
      claim("red")
      report("acp-1", "calm-otter")

      assert.equals("EndOfBuffer:,AgenticTitle:AgentChatTitleRed", prompt_winhighlight())
      local red = require("fishmonger.agent").colours.red
      local title = vim.api.nvim_get_hl(0, { name = "AgentChatTitleRed" })
      local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
      assert.equals(normal.fg, title.fg)
      assert.equals(require("tokyonight.util").blend(red, 0.35, ("#%06x"):format(normal.bg)), ("#%06x"):format(title.bg))
    end)

    it("takes a /color typed by hand from the transcript when there is no claim", function()
      new()
      local transcript = root .. "/session.jsonl"
      vim.fn.writefile({
        vim.json.encode({ type = "agent-color", agentColor = "blue" }),
        vim.json.encode({ type = "agent-color", agentColor = "green" }),
      }, transcript)
      report("acp-1", "calm-otter", { transcript = transcript })

      assert.equals("EndOfBuffer:,AgenticTitle:AgentChatTitleGreen", prompt_winhighlight())
    end)

    it("leaves a session with no colour in agentic's title colour", function()
      new()
      report("acp-1", "calm-otter")

      assert.equals("EndOfBuffer:", prompt_winhighlight())
    end)

    it("paints the prompt agentic opens again when the tab comes back", function()
      new()
      claim("red")
      report("acp-1", "calm-otter")
      fishmonger.show(2)
      fishmonger.show(1)
      -- Painted once agentic has set the new window up; waits on the outcome, not a duration.
      vim.wait(1000, function()
        return prompt_winhighlight():find("AgentChatTitleRed", 1, true) ~= nil
      end)

      assert.equals("EndOfBuffer:,AgenticTitle:AgentChatTitleRed", prompt_winhighlight())
    end)

    it("re-renders its prompt's title when the agents change, to pick up its name", function()
      new()
      rendered = {}
      report("acp-1", "calm-otter")

      assert.same({ key = 1, window = "input" }, rendered[#rendered])
    end)

    it("heads its agent's messages in the chat with its Claude's name", function()
      new()
      report("acp-1", "calm-otter")

      assert.equals("calm-otter", require("plugins.agentic")[1].opts.agent_name("acp-1"))
      assert.is_nil(require("plugins.agentic")[1].opts.agent_name("acp-unknown"))
    end)

    it("titles its prompt with its Claude's name, then agentic's parts", function()
      new()
      report("acp-1", "calm-otter")
      local session = created[1].session

      assert.equals(
        "calm-otter | Prompt | submit: <CR>",
        agent_chat.input_header({ title = "󰦨 Prompt", suffix = "submit: <CR>" }, session.session_state)
      )
      assert.equals("Prompt", agent_chat.input_header({ title = "󰦨 Prompt" }, {}))
    end)
  end)

  it("leaves insert mode in its prompt on Ctrl+N", function()
    new()
    local input = created[1].session.widget.buf_nrs.input
    vim.api.nvim_set_current_win(created[1].session.widget.win_nrs.input)

    vim.api.nvim_feedkeys(vim.keycode("ihello<C-n>x"), "x", false)

    assert.same({ "hell" }, vim.api.nvim_buf_get_lines(input, 0, -1, true))
  end)

  describe("Ctrl keys in its prompt", function()
    local input

    before_each(function()
      new()
      input = created[1].session.widget.buf_nrs.input
      vim.api.nvim_set_current_win(created[1].session.widget.win_nrs.input)
    end)

    after_each(function()
      pcall(vim.keymap.del, "n", "<C-b>")
    end)

    it("run the key's normal-mode mapping, typing nothing", function()
      local ran_in
      vim.keymap.set("n", "<C-b>", function()
        ran_in = vim.api.nvim_get_mode().mode
      end)

      vim.api.nvim_feedkeys(vim.keycode("ihello<C-b>"), "x", false)

      assert.equals("n", ran_in)
      assert.same({ "hello" }, vim.api.nvim_buf_get_lines(input, 0, -1, true))
    end)

    it("type nothing for a key with no mapping that insert mode would type", function()
      vim.api.nvim_feedkeys(vim.keycode("ihi<C-b><C-f><C-z><C-a>x"), "x", false)

      assert.same({ "hix" }, vim.api.nvim_buf_get_lines(input, 0, -1, true))
    end)

    it("keep insert's editing keys", function()
      vim.api.nvim_feedkeys(vim.keycode("ihello world<C-w>x"), "x", false)

      assert.same({ "hello x" }, vim.api.nvim_buf_get_lines(input, 0, -1, true))
    end)
  end)

  describe("Ctrl+C", function()
    local function generating(n)
      created[n].session.is_generating = true
    end

    it("stops only its agent's reply while it is generating, keeping what was typed", function()
      new()
      generating(1)
      vim.api.nvim_set_current_win(created[1].session.widget.win_nrs.input)

      vim.api.nvim_feedkeys(vim.keycode("ihello<C-c> world<Esc>"), "x", false)

      assert.same({ { "reply", 1 } }, stopped)
      assert.same({ "hello world" }, vim.api.nvim_buf_get_lines(created[1].session.widget.buf_nrs.input, 0, -1, true))
    end)

    it("stops it in normal mode from the chat and from a side panel", function()
      new()
      local widget = created[1].session.widget
      for _, buf in ipairs({ widget.buf_nrs.chat, widget.buf_nrs.todos }) do
        generating(1)
        stopped = {}
        vim.api.nvim_win_set_buf(0, buf)

        vim.api.nvim_feedkeys(vim.keycode("<C-c>"), "x", false)

        assert.same({ { "reply", 1 } }, stopped)
      end
    end)

    it("stops the chat it is pressed in, not another one generating", function()
      new()
      new()
      generating(1)
      generating(2)
      vim.api.nvim_set_current_win(created[1].session.widget.win_nrs.input or fishmonger.win)
      vim.api.nvim_win_set_buf(0, created[1].session.widget.buf_nrs.chat)

      vim.api.nvim_feedkeys(vim.keycode("<C-c>"), "x", false)

      assert.same({ { "reply", 1 } }, stopped)
    end)

    -- agentic stops only sub-agents still working, so with none this does nothing.
    it("stops its running sub-agents once its agent isn't replying, keeping what was typed", function()
      new()
      vim.api.nvim_set_current_win(created[1].session.widget.win_nrs.input)

      vim.api.nvim_feedkeys(vim.keycode("ihello<C-c><Esc>"), "x", false)

      assert.same({ { "subagents", 1 } }, stopped)
      assert.same({ "hello" }, vim.api.nvim_buf_get_lines(created[1].session.widget.buf_nrs.input, 0, -1, true))
    end)
  end)

  describe("pasting in its prompt", function()
    local clipboard = require("util.clipboard")
    local text, read_windows = clipboard.text, clipboard.read_windows
    local held_text, held_windows, session
    local clipboard_setting, provider = vim.o.clipboard, vim.g.clipboard

    before_each(function()
      held_text, held_windows = nil, nil
      -- The same text in the + register, for a native put to read.
      vim.o.clipboard = "unnamedplus"
      vim.g.clipboard = {
        name = "spec",
        copy = { ["+"] = function() end, ["*"] = function() end },
        paste = {
          ["+"] = function()
            return held_text and vim.split(held_text, "\n") or {}
          end,
          ["*"] = function()
            return {}
          end,
        },
        cache_enabled = false,
      }
      vim.g.loaded_clipboard_provider = nil
      vim.cmd.runtime("autoload/provider/clipboard.vim")
      clipboard.text = function()
        return held_text
      end
      clipboard.read_windows = function(on_read)
        on_read(held_windows)
      end
      new()
      session = created[1].session
      vim.api.nvim_set_current_win(session.widget.win_nrs.input)
    end)

    after_each(function()
      clipboard.text, clipboard.read_windows = text, read_windows
      vim.o.clipboard, vim.g.clipboard = clipboard_setting, provider
      vim.g.loaded_clipboard_provider = nil
      vim.cmd.runtime("autoload/provider/clipboard.vim")
    end)

    local function paste()
      vim.api.nvim_feedkeys(vim.keycode("i<C-v><Esc>"), "x", false)
    end

    local function typed()
      return vim.api.nvim_buf_get_lines(session.widget.buf_nrs.input, 0, -1, true)
    end

    it("Ctrl+V attaches an image copied on Windows as a PNG file of it", function()
      held_windows = { kind = "image", png = "\137PNG\r\n\26\nbytes" }

      paste()

      assert.equals(1, #session.file_list.files)
      local file = assert(io.open(session.file_list.files[1], "rb"))
      assert.equals("\137PNG\r\n\26\nbytes", file:read("*a"))
      file:close()
      assert.same({ "" }, typed())
    end)

    it("Ctrl+V attaches files copied in Explorer", function()
      local a, b = vim.fn.tempname(), vim.fn.tempname()
      vim.fn.writefile({}, a)
      vim.fn.writefile({}, b)
      held_windows = { kind = "files", paths = { a, b } }

      paste()

      assert.same({ a, b }, session.file_list.files)
    end)

    it("Ctrl+V attaches the file a copied path names, rather than typing it", function()
      local shot = vim.fn.tempname()
      vim.fn.writefile({}, shot)
      held_text = shot

      paste()

      assert.same({ shot }, session.file_list.files)
      assert.same({ "" }, typed())
    end)

    it("Ctrl+V types text", function()
      held_text = "hello /no/such/file"

      paste()

      assert.same({ "hello /no/such/file" }, typed())
      assert.same({}, session.file_list.files)
    end)

    it("Ctrl+V says so when there is nothing to paste", function()
      local said
      local notify = vim.notify
      vim.notify = function(msg, level, opts) ---@diagnostic disable-line: duplicate-set-field, unused-local
        said = msg
      end
      paste()
      vim.notify = notify

      assert.is_not_nil(said)
      assert.same({}, session.file_list.files)
    end)

    --- Normal-mode `keys` in a prompt holding `line`, cursor on its first character.
    local function put(keys, line)
      vim.api.nvim_buf_set_lines(session.widget.buf_nrs.input, 0, -1, true, { line })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.api.nvim_feedkeys(keys, "x", false)
    end

    it("p attaches an image copied on Windows", function()
      held_windows = { kind = "image", png = "\137PNG\r\n\26\nbytes" }

      put("p", "ab")

      assert.equals(1, #session.file_list.files)
      assert.same({ "ab" }, typed())
    end)

    it("P attaches the file a copied path names", function()
      local shot = vim.fn.tempname()
      vim.fn.writefile({}, shot)
      held_text = shot

      put("P", "ab")

      assert.same({ shot }, session.file_list.files)
      assert.same({ "ab" }, typed())
    end)

    it("p puts text after the cursor, as many times as its count", function()
      held_text = "X"

      put("3p", "ab")

      assert.same({ "aXXXb" }, typed())
    end)

    it("P puts text before the cursor", function()
      held_text = "X"

      put("P", "ab")

      assert.same({ "Xab" }, typed())
    end)

    it("p from another register puts that register, whatever the clipboard holds", function()
      held_windows = { kind = "image", png = "\137PNG\r\n\26\nbytes" }
      vim.fn.setreg("a", "R")

      put('"ap', "ab")

      assert.same({ "aRb" }, typed())
      assert.same({}, session.file_list.files)
    end)
  end)

  it("is what fishmonger's <C-b>a makes, as this config sets fishmonger up", function()
    require("plugins.fishmonger")[1].config()
    vim.cmd("stopinsert")

    vim.api.nvim_feedkeys(vim.keycode("<C-b>a"), "x", false)

    assert.equals(1, #created)
    vim.cmd("stopinsert")
  end)
end)

-- Terminal 1's agent chat, as a workspace opens or restores it.
describe("agent_chat.start", function()
  local A = "5acea7d5-42e4-48ab-bae8-c06adaa57027"
  local projects, listed_in, saved_sessions

  before_each(function()
    fresh()
    projects = vim.fn.tempname()
    agent_chat.setup({ claude_projects = projects })
    listed_in, saved_sessions = {}, {}
    package.loaded["agentic.config"] = { provider = "claude-agent-acp" }
    -- The provider's session/list: the directory's sessions, newest first.
    local agent = {
      when_ready = function(self, ready)
        ready(self)
      end,
      list_sessions = function(_, cwd, callback)
        listed_in[#listed_in + 1] = cwd
        callback({ sessions = saved_sessions }, nil)
      end,
    }
    package.loaded["agentic.acp.agent_instance"] = {
      get_instance = function()
        return agent
      end,
    }
  end)

  after_each(function()
    unfake()
    package.loaded["agentic.config"] = nil
    package.loaded["agentic.acp.agent_instance"] = nil
    vim.fn.delete(projects, "rf")
  end)

  --- Start terminal 1's chat in a new tabpage on a directory of its own; waits for it to be hosted.
  local function start(session_id, agent_name)
    vim.cmd("tabnew")
    vim.cmd.tcd(vim.fn.fnameescape(vim.fn.fnamemodify(vim.fn.tempname(), ":h")))
    local tab = vim.api.nvim_get_current_tabpage()
    agent_chat.start(tab, session_id, agent_name)
    vim.wait(1000, function()
      return #created > 0
    end)
    return tab
  end

  it("resumes the session it is given in terminal 1, in the directory its transcript records", function()
    vim.fn.mkdir(projects .. "/-elsewhere", "p")
    vim.fn.writefile({ vim.json.encode({ type = "user", cwd = "/elsewhere" }) }, projects .. "/-elsewhere/" .. A .. ".jsonl")

    local tab = start(A)

    assert.same({ kind = "load", session_id = A, cwd = "/elsewhere" }, {
      kind = created[1].kind,
      session_id = created[1].session_id,
      cwd = created[1].cwd,
    })
    assert.same({ 1 }, vim.tbl_map(function(t)
      return t.slot
    end, fishmonger.tabs(tab)))
    assert.equals(created[1].session.widget.buf_nrs.chat, vim.api.nvim_win_get_buf(fishmonger.win))
  end)

  it("resumes in the tabpage's directory a session whose transcript records none", function()
    start(A)

    assert.equals("load", created[1].kind)
    assert.equals(vim.fn.getcwd(), created[1].cwd)
  end)

  it("without a session, resumes the newest in the tabpage's directory, as claude --continue", function()
    saved_sessions = { { sessionId = A, cwd = "/x" }, { sessionId = "older", cwd = "/x" } }

    start()

    assert.same({ vim.fn.getcwd() }, listed_in)
    assert.same({ kind = "load", session_id = A, cwd = vim.fn.getcwd() }, {
      kind = created[1].kind,
      session_id = created[1].session_id,
      cwd = created[1].cwd,
    })
  end)

  it("starts a new session when the directory has none", function()
    start()

    assert.equals("new", created[1].kind)
    assert.equals(vim.fn.getcwd(), created[1].cwd)
  end)

  it("leaves terminal 1 alone when something already took it", function()
    vim.cmd("tabnew")
    local tab = vim.api.nvim_get_current_tabpage()
    fishmonger.show(1)

    agent_chat.start(tab, A)

    assert.same({}, created)
  end)

  it("leaves focus in the window it was in", function()
    vim.cmd("tabnew")
    local editor = vim.api.nvim_get_current_win()

    agent_chat.start(vim.api.nvim_get_current_tabpage(), A)

    assert.equals(1, #created)
    assert.equals(editor, vim.api.nvim_get_current_win())
  end)

  -- What the session-identity mod reads to give terminal 1's Claude its role or agent name.
  for _, case in ipairs({ { session_id = A, kind = "load" }, { kind = "new" } }) do
    it("tells a " .. case.kind .. " session's Claude it is terminal 1's, and the name to take", function()
      start(case.session_id, "keen-heron")

      assert.equals(case.kind, created[1].kind)
      assert.same(
        { claudeCode = { options = { env = { WORKSPACE_TERMINAL = "1", CLAUDE_AGENT_NAME = "keen-heron" } } } },
        created[1].meta
      )
    end)
  end

  it("tells terminal 1's Claude no name when it has none to take", function()
    start(A)

    assert.same({ claudeCode = { options = { env = { WORKSPACE_TERMINAL = "1" } } } }, created[1].meta)
  end)
end)

describe("the agentic config", function()
  --- Whether `text` has an emoji or an icon-font glyph (Unicode's private use areas, where Nerd Fonts live).
  local function pictographic(text)
    for _, code in ipairs(vim.fn.str2list(text)) do
      if code >= 0x1F000 or (code >= 0x2600 and code <= 0x26FF) or code == 0xFE0F or (code >= 0xE000 and code <= 0xF8FF) then
        return true
      end
    end
    return false
  end

  it("draws no emoji or icon glyphs in the chat's headings, titles, buffer names and spinner", function()
    vim.opt.runtimepath:prepend(vim.fn.expand("~/dev/agentic.nvim"))
    local opts = require("plugins.agentic")[1].opts
    local config = vim.tbl_deep_extend("force", require("agentic.config_default"), opts)
    local shown = {}
    for _, group in ipairs({ "chat_icons", "message_icons", "diagnostic_icons" }) do
      vim.list_extend(shown, vim.tbl_values(config[group]))
    end
    for _, frames in pairs(config.spinner_chars) do
      vim.list_extend(shown, frames)
    end
    for name, header in pairs(require("agentic.ui.window_decoration").default_headers()) do
      local own = config.headers[name]
      if type(own) ~= "function" then -- the prompt's is drawn by input_header, below
        shown[#shown + 1] = own and own.title or header.title
      end
    end
    shown[#shown + 1] = require("config.agent_chat").input_header({ title = "󰦨 Prompt" }, {})
    -- Without a buffer_name agentic names the prompt's buffer after its default title.
    shown[#shown + 1] = config.windows.input.buffer_name
      or require("agentic.ui.window_decoration").default_headers().input.title

    assert.same({}, vim.tbl_filter(pictographic, shown))
  end)

  it("summarises a sub-agent's activity on its Agent call rather than listing its calls", function()
    vim.opt.runtimepath:prepend(vim.fn.expand("~/dev/agentic.nvim"))
    local config = vim.tbl_deep_extend("force", require("agentic.config_default"), require("plugins.agentic")[1].opts)

    assert.equals("summary", config.tool_calls.subagent_activity)
  end)
end)
