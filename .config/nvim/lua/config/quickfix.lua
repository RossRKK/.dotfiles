-- The quickfix list as a place the editor and agents share: an agent sets one (`nvim-qf set`), it docks under
-- the main window, and the entries the cursor has been on are remembered, so `nvim-qf state` can say where I am.
local M = {}

local windows = require("config.windows")

-- A list shorter than this gets a row per entry; a longer one scrolls.
local MAX_HEIGHT = 5

-- Entry indices the cursor has been on, by quickfix list id.
local visited = {} ---@type table<integer, table<integer, true>>

local mark_visited, step, view_window

---@class quickfix.Entry
---@field path string
---@field line integer 1-based
---@field col? integer 1-based
---@field text string

---@class quickfix.State
---@field id integer
---@field title string
---@field current integer 1-based index of the current entry
---@field visited integer[] 1-based indices, ascending
---@field changedtick integer
---@field entries quickfix.Entry[]

--- Remember visited entries, and step through the list in the main window from any window.
function M.setup()
  vim.api.nvim_create_autocmd({ "CursorMoved", "BufEnter" }, {
    group = vim.api.nvim_create_augroup("quickfix_visited", { clear = true }),
    callback = function(ev)
      mark_visited(ev.buf, vim.api.nvim_win_get_cursor(0)[1])
    end,
  })
  -- The builtins, but landing in the main window: from the agent chat they would open the file over it.
  for lhs, cmd in pairs({
    ["]q"] = "cnext",
    ["[q"] = "cprevious",
    ["]Q"] = "clast",
    ["[Q"] = "cfirst",
  }) do
    vim.keymap.set("n", lhs, function()
      step(cmd)
    end, { desc = ":" .. cmd .. " in the main window" })
  end
end

--- Make `entries` the current quickfix list, titled `title`, and dock it under the main window.
---@param title string
---@param entries quickfix.Entry[]
---@return integer id the new list's
function M.set(title, entries)
  vim.fn.setqflist({}, " ", {
    title = title,
    items = vim.tbl_map(function(entry)
      return { filename = entry.path, lnum = entry.line, col = entry.col, text = entry.text }
    end, entries),
  })
  M.show(0)
  return vim.fn.getqflist({ id = 0 }).id
end

--- Dock the quickfix window under `tab`'s main window, sized to the list, keeping focus where it is.
---@param tab integer tabpage handle (0: current)
function M.show(tab)
  local height = math.max(1, math.min(vim.fn.getqflist({ size = 0 }).size, MAX_HEIGHT))
  local open = view_window(tab)
  if open then
    vim.api.nvim_win_set_height(open, height)
    return
  end
  local main = windows.main_window(tab)
  vim.api.nvim_win_call(main or vim.api.nvim_tabpage_get_win(tab), function()
    vim.cmd((main and "belowright" or "botright") .. " copen " .. height)
  end)
  vim.wo[view_window(tab)].winfixheight = true
end

--- The current quickfix list and where I am in it, or nil when it is empty.
---@return quickfix.State?
function M.state()
  local list =
    vim.fn.getqflist({ id = 0, title = 0, idx = 0, size = 0, changedtick = 0, items = 0 })
  if list.size == 0 then
    return nil
  end
  local seen = vim.tbl_keys(visited[list.id] or {})
  table.sort(seen)
  return {
    id = list.id,
    title = list.title,
    current = list.idx,
    visited = seen,
    changedtick = list.changedtick,
    entries = vim.tbl_map(function(item)
      return {
        path = item.bufnr ~= 0
            and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(item.bufnr), ":~:.")
          or "",
        line = item.lnum,
        text = item.text,
      }
    end, list.items),
  }
end

-- Entry indices by buffer, per list, rebuilt when the list changes: CursorMoved runs on every keystroke, and a
-- grep's list can hold thousands. Buffers stay put as lines shift; line numbers are read live.
local by_buffer = {} ---@type table<integer, { changedtick: integer, entries: table<integer, integer[]> }>

---@param id integer
---@return table<integer, integer[]>
local function entries_by_buffer(id)
  local tick = vim.fn.getqflist({ id = id, changedtick = 0 }).changedtick
  local index = by_buffer[id]
  if not index or index.changedtick ~= tick then
    index = { changedtick = tick, entries = {} }
    for idx, item in ipairs(vim.fn.getqflist({ id = id, items = 0 }).items) do
      index.entries[item.bufnr] = index.entries[item.bufnr] or {}
      table.insert(index.entries[item.bufnr], idx)
    end
    by_buffer[id] = index
  end
  return index.entries
end

--- Record the current list's entries at `line` of `buf` as visited.
---@param buf integer
---@param line integer
function mark_visited(buf, line)
  local id = vim.fn.getqflist({ id = 0 }).id
  if id == 0 then
    return
  end
  for _, idx in ipairs(entries_by_buffer(id)[buf] or {}) do
    if vim.fn.getqflist({ id = id, idx = idx, items = 0 }).items[1].lnum == line then
      visited[id] = visited[id] or {}
      visited[id][idx] = true
    end
  end
end

--- Run quickfix motion `cmd` with the typed count from the main window.
---@param cmd "cnext"|"cprevious"|"clast"|"cfirst"
function step(cmd)
  windows.goto_main_window()
  -- A count to cfirst/clast is an entry number, so none means the first or last, not entry 1.
  local count = (cmd == "cnext" or cmd == "cprevious") and vim.v.count1
    or (vim.v.count > 0 and vim.v.count or "")
  local ok, err = pcall(vim.cmd, count .. cmd)
  if not ok then
    vim.notify((tostring(err):gsub("^Vim:", "")), vim.log.levels.ERROR)
  end
end

--- `tab`'s quickfix window, or nil.
---@param tab integer
---@return integer?
function view_window(tab)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    local info = vim.fn.getwininfo(win)[1]
    if info.quickfix == 1 and info.loclist == 0 then
      return win
    end
  end
end

return M
