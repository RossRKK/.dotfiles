-- Agent chats are fishmonger tabs: each tab holds one agentic.nvim session, its
-- chat in the tab's window with the prompt and panels stacked under it, started
-- in the workspace's directory. The one place that knows both plugins.

local M = {}

-- agentic.nvim's documented filetype for its chat buffer: what makes a tab an agent tab.
local CHAT_FILETYPE = "AgenticChat"

local agent_slot, new_chat -- defined below their caller

-- Space+i: shows this tabpage's agent tab, making one if it has none, or closes
-- the panel when that tab is already showing there.
function M.toggle()
  local fishmonger = require("fishmonger")
  local tab = vim.api.nvim_get_current_tabpage()
  local slot = agent_slot()
  if slot and slot == fishmonger.current and fishmonger.panel_open(tab) then
    fishmonger.toggle()
  elseif slot then
    fishmonger.show(slot)
  else
    new_chat(tab)
  end
end

-- This tabpage's agent tab: the current one if it is an agent, else the lowest numbered.
function agent_slot()
  local fishmonger = require("fishmonger")
  local function is_agent(slot)
    local term = fishmonger.slots[slot]
    return term and vim.bo[term.buf].filetype == CHAT_FILETYPE
  end
  if fishmonger.current and is_agent(fishmonger.current) then
    return fishmonger.current
  end
  for slot = 1, 9 do
    if is_agent(slot) then
      return slot
    end
  end
end

-- A new agent tab in the lowest free slot, its session started in the directory
-- fishmonger gives the tabpage rather than the focused window's.
function new_chat(tab)
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
