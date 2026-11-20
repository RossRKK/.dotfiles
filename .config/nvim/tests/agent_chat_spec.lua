-- config.agent_chat: an agent chat is a fishmonger tab. Runs the real
-- fishmonger (its shells faked, as in its own suite) against a fake
-- agentic session registry that records what the glue asks of it.

local assert = require("luassert")

local agent_chat, fishmonger
local created, shown, hidden, destroyed, rendered

--- A fake agentic session whose chat buffer has agentic's filetype, its prompt
--- opened under the chat on show as agentic's is.
local function fake_session(key)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "AgenticChat"
  local widget
  widget = {
    buf_nrs = { chat = buf, input = vim.api.nvim_create_buf(false, true) },
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
  return { session_key = key, session_id = "acp-" .. key, session_state = {}, widget = widget }
end

local function fake_registry()
  local sessions = {}
  return {
    create = function(provider, spec) ---@diagnostic disable-line: unused-local
      local session = fake_session(#created + 1)
      created[#created + 1] = { session = session, cwd = spec.cwd(vim.fn.getcwd()) }
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

describe("agent_chat.new", function()
  local jobstart = vim.fn.jobstart

  before_each(function()
    pcall(vim.cmd, "tabonly!")
    pcall(vim.cmd, "only!")
    vim.w.fishmonger_side = nil
    created, shown, hidden, destroyed, rendered = {}, {}, {}, {}, {}
    -- Keep jobstart's real arity, as fishmonger's own suite does.
    vim.fn.jobstart = function(cmd, opts) ---@diagnostic disable-line: duplicate-set-field, unused-local
      return 1
    end
    package.loaded["fishmonger"] = nil
    fishmonger = require("fishmonger")
    fishmonger.setup_exit()
    package.loaded["agentic.session_registry"] = fake_registry()
    package.loaded["config.agent_chat"] = nil
    agent_chat = require("config.agent_chat")
  end)

  after_each(function()
    vim.fn.jobstart = jobstart
    package.loaded["agentic.session_registry"] = nil
    package.loaded["fishmonger"] = nil
  end)

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
      assert.equals(require("fishmonger.agent").colours.red, ("#%06x"):format(vim.api.nvim_get_hl(0, { name = "AgentChatTitleRed" }).bg))
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

  it("is what fishmonger's <C-b>a makes, as this config sets fishmonger up", function()
    require("plugins.fishmonger")[1].config()
    vim.cmd("stopinsert")

    vim.api.nvim_feedkeys(vim.keycode("<C-b>a"), "x", false)

    assert.equals(1, #created)
    vim.cmd("stopinsert")
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
end)
