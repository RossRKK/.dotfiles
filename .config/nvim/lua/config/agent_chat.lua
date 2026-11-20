-- The agentic.nvim chat and fishmonger's side terminal both want the right
-- edge, so toggling the chat swaps them: opening it hides a showing terminal,
-- closing it brings back only a terminal it hid. Per tabpage, as workspaces are.

local M = {}

-- agentic.nvim has no "is the chat visible" API; its documented filetype is the next best public signal.
local CHAT_FILETYPE = "AgenticChat"

local chat_visible, open, close -- defined below their caller

function M.toggle()
  local tab = vim.api.nvim_get_current_tabpage()
  if chat_visible(tab) then
    close(tab)
  else
    open(tab)
  end
end

-- A split, not a float: agentic keeps a hidden float of the chat buffer while the chat is closed.
function chat_visible(tab)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if
      vim.bo[vim.api.nvim_win_get_buf(win)].filetype == CHAT_FILETYPE
      and vim.api.nvim_win_get_config(win).relative == ""
    then
      return true
    end
  end
  return false
end

function open(tab)
  local fishmonger = require("fishmonger")
  if fishmonger.panel_open(tab) then
    fishmonger.toggle()
    vim.t[tab].agent_chat_hid_terminal = true
  end
  require("agentic").open()
end

function close(tab)
  require("agentic").close()
  if vim.t[tab].agent_chat_hid_terminal then
    vim.t[tab].agent_chat_hid_terminal = nil
    local fishmonger = require("fishmonger")
    if not fishmonger.panel_open(tab) then
      fishmonger.toggle()
    end
  end
end

return M
