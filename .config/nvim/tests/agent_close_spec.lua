-- Closing a tab with an agent chat in it ends the chat's agentic session before
-- anything the agent already sent can reach the chat's wiped buffers. Runs the
-- full config in a child nvim against a stand-in agent that only opens a session.

local assert = require("luassert")
local plugins = require("tests.helpers.plugins")

local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")

describe("closing a tab with an agent chat", function()
  it("ends its session, an update already on its way dropped without an error", function()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    local out = root .. "/report.json"
    local env = vim.fn.environ()
    for _, name in ipairs({ "NVIM", "VIM", "VIMRUNTIME", "AGENT_WORKTREES", "TMUX" }) do
      env[name] = nil
    end
    env.XDG_STATE_HOME = root .. "/state"
    env.NVIM_CONFIG_DIR = vim.fn.fnamemodify(here, ":h")
    env.PROBE_OUT = out
    env.FAKE_AGENT = here .. "/helpers/fake_acp_agent.py"
    local res = vim
      .system(
        { plugins.nvim(), "--headless", "--cmd", "luafile " .. here .. "/helpers/agent_close_probe.lua" },
        { env = env, clear_env = true, text = true, cwd = root }
      )
      :wait(60000)
    assert.equals(0, res.code, res.stderr)
    local report = vim.json.decode(table.concat(vim.fn.readfile(out), "\n"))
    vim.fn.delete(root, "rf")

    assert.is_nil(report.error)
    -- agentic's own errors: the full config's other startup work can set v:errmsg in this nvim too.
    assert.is_nil(report.errmsg:find("agentic", 1, true), report.errmsg)
    assert.equals(0, report.sessions)
  end)
end)
