-- Agent chats are fishmonger tabs: each tab holds one agentic.nvim session, its
-- chat in the tab's window with the prompt and panels stacked under it, started
-- in the workspace's directory. The one place that knows both plugins.

local M = {}

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
  })
  if not hosted then
    registry.destroy(key)
  end
end

return M
