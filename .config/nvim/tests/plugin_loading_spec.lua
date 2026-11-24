-- The full config's plugins load through lazy.nvim, so their specs' opts and
-- config apply, wherever the plugins come from (lazy's install or the nix build).
-- Runs the full config in a child: the nvim under test, on this checkout's config.

local assert = require("luassert")
local plugins = require("tests.helpers.plugins")

local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")

--- The probe's report from a child nvim started with the full config.
---@return table
local function probe()
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
  local res = vim
    .system(
      { plugins.nvim(), "--headless", "--cmd", "luafile " .. here .. "/helpers/plugin_loading_probe.lua" },
      { env = env, clear_env = true, text = true }
    )
    :wait(60000)
  assert.equals(0, res.code, res.stderr)
  local report = vim.json.decode(table.concat(vim.fn.readfile(out), "\n"))
  vim.fn.delete(root, "rf")
  return report
end

describe("the full config's plugins", function()
  local report
  before_each(function()
    report = report or probe()
    assert.is_nil(report.error)
  end)

  it("each sit in a directory lazy.nvim can tell them by", function()
    assert.same({}, report.unidentified)
  end)

  it("load with their spec's opts when first required", function()
    assert.is_true(report.agentic_loaded)
    assert.is_false(report.agentic_preselect)
    assert.equals("summary", report.agentic_subagent_activity)
  end)

  it("attach render-markdown to snacks' gh buffers, so their comments below the first screen render", function()
    assert.is_true(report.gh_buffer_attached)
  end)
end)
