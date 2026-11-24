-- Run inside the child nvim plugin_loading_spec starts with the full config:
-- reports how plugins load, as JSON to the file named by $PROBE_OUT, then quits.

local gh_buffer_attached -- defined below report

local function report()
  local plugins = require("lazy.core.config").plugins

  -- lazy loads a plugin on require() only when it can tell the module's plugin
  -- from its file's path, by the name of the directory above lua/. Plugins it
  -- can't: a require() of one loads it without its spec's opts or config.
  local unidentified = {}
  for name, plugin in pairs(plugins) do
    if require("lazy.core.plugin").find(plugin.dir .. "/lua/probe.lua") ~= plugin then
      unidentified[#unidentified + 1] = name .. " (" .. plugin.dir .. ")"
    end
  end
  table.sort(unidentified)

  require("agentic")
  local agentic = require("agentic.config")
  return {
    gh_buffer_attached = gh_buffer_attached(),
    unidentified = unidentified,
    agentic_loaded = plugins["agentic.nvim"]._.loaded ~= nil,
    agentic_preselect = agentic.completion.preselect,
    agentic_subagent_activity = agentic.tool_calls.subagent_activity,
  }
end

--- Whether render-markdown attaches to a buffer of the filetype snacks gives its gh:// buffers,
--- so it redraws the rows scrolled into view and not only the first screen.
---@return boolean
function gh_buffer_attached()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_win_set_buf(0, buf)
  vim.bo[buf].filetype = "markdown.gh"
  return require("render-markdown.core.manager").attached(buf)
end

-- After startup's own loads (lazy's VeryLazy never fires headless).
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = vim.schedule_wrap(function()
    local ok, result = pcall(report)
    vim.fn.writefile({ vim.json.encode(ok and result or { error = result }) }, vim.env.PROBE_OUT)
    vim.cmd("qa!")
  end),
})
