-- Loaded inside the child nvim that workspace_tabs_spec drives: reads its layout and screen back out.

local M = {}

--- Terminal 1 runs sh rather than Claude, so fishmonger still builds its window but no agent starts.
function M.stub_claude()
  local fishmonger = require("fishmonger")
  local show = fishmonger.show
  fishmonger.show = function(slot, opts)
    return show(slot, vim.tbl_extend("force", opts or {}, { shell = { "sh" } }))
  end
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
