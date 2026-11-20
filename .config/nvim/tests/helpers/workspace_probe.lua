-- Loaded inside the child nvim that workspace_tabs_spec drives: reads its layout and screen back out.

local M = {}

--- Terminal 1 runs sh rather than Claude or an agent chat, so fishmonger still builds its window but no agent starts.
function M.stub_claude()
  local fishmonger = require("fishmonger")
  local show = fishmonger.show
  fishmonger.show = function(slot, opts)
    return show(slot, vim.tbl_extend("force", opts or {}, { shell = { "sh" } }))
  end
  require("config.agent_chat").start = function(tab, session_id)
    vim.api.nvim_tabpage_set_var(tab, "probe_chat", { session = session_id })
    fishmonger.show(1, { tab = tab, insert = false })
  end
end

--- agentic's provider swapped for one that never answers, so a chat's windows open with no Claude behind them.
function M.stand_in_agent()
  local provider = require("agentic.config").acp_providers["claude-agent-acp"]
  -- Exits when nvim does, as its stdin closes.
  provider.command, provider.args = "sh", { "-c", "cat >/dev/null" }
end

--- The newest agent chat's widget windows.
---@return table<string, integer>
local function chat_windows()
  local sessions = require("agentic.session_registry").list()
  return #sessions > 0 and sessions[#sessions].widget.win_nrs or {}
end

--- The newest agent chat's prompt height, or vim.NIL before its prompt is open.
---@return integer|vim.NIL
function M.prompt_height()
  local input = chat_windows().input
  return input and vim.api.nvim_win_is_valid(input) and vim.api.nvim_win_get_height(input)
    or vim.NIL
end

--- Focus the newest agent chat's chat window.
function M.focus_chat()
  vim.api.nvim_set_current_win(assert(chat_windows().chat))
end

--- Terminal 1's agent chat in `tab` once started, with the session it resumed; vim.NIL before.
---@param tab integer
---@return { session?: string }|vim.NIL
function M.chat(tab)
  local ok, chat = pcall(vim.api.nvim_tabpage_get_var, tab, "probe_chat")
  return ok and chat or vim.NIL
end

--- A tabpage's window tree with each window shown as its buffer's filetype.
---@param tab integer
---@return string
function M.shape(tab)
  local function walk(node)
    if node[1] == "leaf" then
      local ft = vim.bo[vim.api.nvim_win_get_buf(node[2])].filetype
      return ft == "" and "editor" or ft
    end
    return node[1] .. "[" .. table.concat(vim.tbl_map(walk, node[2]), ", ") .. "]"
  end
  return walk(vim.fn.winlayout(vim.api.nvim_tabpage_get_number(tab)))
end

--- Whether every window a workspace tab gets is up in `tab`.
---@param tab integer
---@return boolean
function M.built(tab)
  local shape = M.shape(tab)
  for _, ft in ipairs({ "neo-tree", "snacks_dashboard", "markdown", "fishmonger" }) do
    if not shape:find(ft, 1, true) then
      return false
    end
  end
  return true
end

--- The screen rows lualine's mode is drawn on, and the row a global statusline takes.
---@return { rows: integer[], bottom: integer }
function M.statusline()
  vim.cmd.redraw()
  local rows = {}
  for row = 1, vim.o.lines do
    local text = {}
    for col = 1, vim.o.columns do
      text[#text + 1] = vim.fn.screenstring(row, col)
    end
    local line = table.concat(text)
    if line:find("%f[%w]NORMAL%f[%W]") or line:find("%f[%w]TERMINAL%f[%W]") then
      rows[#rows + 1] = row
    end
  end
  return { rows = rows, bottom = vim.o.lines - vim.o.cmdheight }
end

--- The current tab's file tree, once it has drawn the node for `path`.
---@param path string
---@return neotree.State?
function M.tree_with(path)
  local state = require("neo-tree.sources.manager").get_state("filesystem")
  if state.tree and state.tree:get_node(path) then
    return state
  end
end

--- Open `path` as <CR> on its node in the tree does, from wherever focus is now.
---@param path string
function M.open_from_tree(path)
  local state = assert(M.tree_with(path))
  vim.api.nvim_set_current_win(state.winid)
  require("neo-tree.ui.renderer").focus_node(state, path)
  require("neo-tree.sources.filesystem.commands").open(state)
end

--- The workspace tabs, by workspace number.
---@return integer[]
function M.workspaces()
  local ws = require("config.workspace")
  local tabs = vim.tbl_filter(function(tab)
    return ws.slot(tab) ~= nil
  end, vim.api.nvim_list_tabpages())
  table.sort(tabs, function(a, b)
    return ws.slot(a) < ws.slot(b)
  end)
  return tabs
end

return M
