-- tmux-window-style tabs for the vertical side terminal (native backend only).
--
-- One terminal occupies the side slot at a time; the others stay alive but
-- hidden, listed in a winbar tab strip across the top of the terminal window
-- (like tmux's window list). <C-b>{1-9} swaps which terminal fills the slot,
-- creating it on demand; <C-b>c opens the next free slot; <C-b>, renames the
-- current tab. This is only wired up when ide.terminal_backend == "native"
-- (see terminal.lua) — in tmux mode real tmux windows do this job instead.

local ide = require("config.ide")

local M = {}

local BASE = 1 -- terminal 1 is the primary side terminal (<C-t>)
local MAX = 9

M.current = BASE -- count of the terminal currently shown
M.names = {} -- optional display name per count (via rename)

local function tterm()
  return require("toggleterm.terminal")
end

-- Our side terminals: vertical, counts 1..9, including hidden ones so a tab
-- persists after you switch away from it (tmux-window semantics).
local function managed()
  local out = {}
  for _, t in ipairs(tterm().get_all(true)) do
    if t.direction == "vertical" and type(t.id) == "number" and t.id >= BASE and t.id <= MAX then
      out[#out + 1] = t
    end
  end
  table.sort(out, function(a, b)
    return a.id < b.id
  end)
  return out
end

local function open_managed()
  for _, t in ipairs(managed()) do
    if t:is_open() then
      return t
    end
  end
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local data = f:read("*a")
  f:close()
  return data
end

-- Resolve a terminal's shell pid and its controlling-terminal foreground
-- process group (tpgid, field 8 of /proc/<pid>/stat — the fields after the
-- "(comm)" are [1]=state [2]=ppid [3]=pgrp [4]=session [5]=tty_nr [6]=tpgid).
local function term_procs(id)
  local t = tterm().get(id, true)
  if not t or not t.job_id then
    return nil
  end
  local ok, pid = pcall(vim.fn.jobpid, t.job_id)
  if not ok or type(pid) ~= "number" then
    return nil
  end
  local stat = read_file("/proc/" .. pid .. "/stat")
  local tpgid
  if stat then
    local after = stat:match("%)%s*(.*)$")
    local fields = after and vim.split(after, " ", { trimempty = true }) or {}
    tpgid = tonumber(fields[6])
  end
  return pid, tpgid
end

-- Repaint the app in a terminal by sending SIGWINCH to its foreground process
-- group. While a tab is hidden, Claude Code (and other mode-2026 TUIs) stream
-- into a grid with no visible window to flush to, so it desyncs and shows
-- torn/duplicated text when re-shown. SIGWINCH makes the app re-render at the
-- *current* size — we never resize nvim's window, so there's no reflow and no
-- off-by-one line shift (unlike a width nudge).
local function force_repaint(id)
  local pid, tpgid = term_procs(id)
  if not pid then
    return false
  end
  local group = (tpgid and tpgid > 0) and tpgid or pid
  vim.system({ "kill", "-WINCH", "-" .. group })
  return true
end

-- Show terminal `count`, creating it if it doesn't exist yet. Any other managed
-- terminal occupying the slot is hidden (not killed) so it stays a tab.
function M.show(count)
  count = math.max(BASE, math.min(MAX, count))
  local existing = tterm().get(count, true)

  for _, t in ipairs(managed()) do
    if t.id ~= count and t:is_open() then
      t:close()
    end
  end

  if existing and existing:is_open() then
    if existing.window and vim.api.nvim_win_is_valid(existing.window) then
      vim.api.nvim_set_current_win(existing.window)
    end
  else
    -- toggle() creates-or-shows using the global toggleterm config, so shell,
    -- on_open (winfixwidth, width, <C-k> passthrough) all apply.
    require("toggleterm").toggle(count, ide.term_width(), nil, "vertical")
  end

  M.current = count
  vim.schedule(function()
    M.refresh_winbar()
    vim.cmd("startinsert")
  end)
end

-- <C-b>r: manually repaint the visible terminal, to clear any tearing left over
-- from streaming into it while it was hidden (see force_repaint).
function M.repaint()
  local t = open_managed()
  if t and force_repaint(t.id) then
    vim.notify("terminal " .. tostring(t.id) .. " repainted (SIGWINCH)", vim.log.levels.INFO)
  else
    vim.notify("no visible terminal to repaint", vim.log.levels.WARN)
  end
end

-- <C-t>: toggle the side slot — hide it if open, else re-show the current tab.
function M.toggle()
  local open = open_managed()
  if open then
    open:close()
  else
    M.show(M.current or BASE)
  end
end

-- <C-b>c: open the lowest unused slot.
function M.new()
  local used = {}
  for _, t in ipairs(managed()) do
    used[t.id] = true
  end
  for i = BASE, MAX do
    if not used[i] then
      M.show(i)
      return
    end
  end
  vim.notify("all " .. MAX .. " terminal slots in use", vim.log.levels.WARN)
end

-- <C-b>,: rename the current tab.
function M.rename()
  local count = M.current or BASE
  vim.ui.input({ prompt = "Rename terminal " .. count .. ": ", default = M.names[count] or "" }, function(name)
    if name == nil then
      return
    end
    M.names[count] = name ~= "" and name or nil
    M.refresh_winbar()
  end)
end

-- The command running in a terminal's pty foreground (like tmux's automatic
-- window rename); the shell itself when nothing else is in the foreground.
local function foreground_comm(id)
  local pid, tpgid = term_procs(id)
  if not pid then
    return nil
  end
  local target = (tpgid and tpgid > 0) and tpgid or pid
  local comm = read_file("/proc/" .. target .. "/comm")
  return comm and (comm:gsub("%s+$", "")) or nil
end

-- Manual rename wins; otherwise the live foreground process; otherwise "term".
local function label(id)
  local name = M.names[id] or foreground_comm(id) or "term"
  return string.format(" %d:%s ", id, name)
end

-- Winbar content: one clickable segment per tab, active one highlighted.
function M.tabline()
  local parts = {}
  for _, t in ipairs(managed()) do
    local hl = (t.id == M.current) and "%#TabLineSel#" or "%#TabLine#"
    parts[#parts + 1] = string.format("%%%d@v:lua.__toggleterm_tab_click@%s%s%%X", t.id, hl, label(t.id))
  end
  return table.concat(parts) .. "%#TabLineFill#"
end

-- Winbar tab strip disabled for now: it stole a pty row and destabilised
-- Claude Code's inline rendering (margin line + off-by-one on repaint). The tab
-- switching (<C-b>{1-9}) still works; there's just no visible strip. No-op kept
-- so callers don't need to change.
function M.refresh_winbar() end

_G.__toggleterm_tabline = M.tabline
_G.__toggleterm_tab_click = function(minwid)
  M.show(minwid)
end

-- Install the tmux-style keymaps (native backend only). Called from terminal.lua.
function M.setup_keymaps()
  local map = vim.keymap.set
  for i = BASE, MAX do
    map({ "n", "t" }, "<C-b>" .. i, function()
      M.show(i)
    end, { desc = "Terminal tab " .. i })
  end
  map({ "n", "t" }, "<C-b>c", M.new, { desc = "New terminal tab" })
  map({ "n", "t" }, "<C-b>,", M.rename, { desc = "Rename terminal tab" })
  map({ "n", "t" }, "<C-b>r", M.repaint, { desc = "Repaint terminal (clear tearing)" })
  map({ "n", "t" }, "<C-t>", M.toggle, { desc = "Toggle side terminal" })
end

return M
