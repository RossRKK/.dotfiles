-- config.agent_chat: an agent chat is a fishmonger tab. Runs the real
-- fishmonger (its shells faked, as in its own suite) against a fake
-- agentic session registry that records what the glue asks of it.

local assert = require("luassert")

local agent_chat, fishmonger
local created, shown, hidden, destroyed

--- A fake agentic session whose chat buffer has agentic's filetype.
local function fake_session(key)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "AgenticChat"
  return {
    session_key = key,
    session_id = "acp-" .. key,
    widget = {
      buf_nrs = { chat = buf },
      hide = function()
        hidden[#hidden + 1] = key
      end,
    },
  }
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
    created, shown, hidden, destroyed = {}, {}, {}, {}
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
      agent_chat.setup({ claude_sessions = root .. "/sessions" })
    end)

    --- Report ACP session `id` as agent-status and Claude would: its status, and its name.
    local function report(id, name)
      local pid = vim.fn.getpid() -- alive, so the record survives the liveness check
      vim.fn.writefile({ vim.json.encode({ session = id, state = "done", agent_pid = pid, pids = { pid } }) }, root .. "/agents/" .. id .. ".json")
      vim.fn.writefile({ vim.json.encode({ pid = pid, name = name }) }, root .. "/sessions/" .. pid .. ".json")
      require("fishmonger").refresh_agents()
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
  end)

  it("is what fishmonger's <C-b>A makes, as this config sets fishmonger up", function()
    require("plugins.fishmonger")[1].config()
    vim.cmd("stopinsert")

    vim.api.nvim_feedkeys(vim.keycode("<C-b>A"), "x", false)

    assert.equals(1, #created)
    vim.cmd("stopinsert")
  end)
end)
