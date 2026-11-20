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

describe("agent_chat.toggle", function()
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

  it("opens a new agent tab in the panel and shows its session there", function()
    agent_chat.toggle()

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

    agent_chat.toggle()

    assert.are_not.equal(root, tab_dir)
    assert.equals(tab_dir, created[1].cwd)
  end)

  it("goes back to the agent tab rather than making another", function()
    agent_chat.toggle()
    fishmonger.show(2)
    agent_chat.toggle()

    assert.equals(1, #created)
    assert.equals(1, fishmonger.current)
    assert.same({ 1 }, hidden) -- slot 2's shell took the window first
  end)

  it("closes the panel when the agent tab is already showing, hiding the session", function()
    agent_chat.toggle()
    agent_chat.toggle()

    assert.is_false(fishmonger.panel_open())
    assert.same({ 1 }, hidden)
  end)

  it("gives each workspace its own agent tab", function()
    agent_chat.toggle()
    vim.cmd("tabnew")
    agent_chat.toggle()

    assert.equals(2, #created)
  end)

  it("ends the session when its tab is killed", function()
    agent_chat.toggle()
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
    agent_chat.toggle()
    vim.notify = notify

    assert.same({ 1 }, destroyed)
  end)
end)
