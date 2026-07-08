-- tmux-style tab switching for the vertical side terminal (native backend only).
--
-- One terminal occupies the side slot at a time; the others stay alive but
-- hidden. Switching is done from terminal-normal mode (enter it with <C-\><C-n>,
-- or the <C-n> map): <C-b>{1-9} switches to (creating on demand) a terminal,
-- <C-b>c opens the next free slot, <C-b>r repaints the visible terminal. <C-t>
-- toggles the side slot from anywhere. Wired up only when
-- ide.terminal_backend == "native" (see terminal.lua); in tmux mode real tmux
-- windows do this job instead.
--
-- There's no visible tab strip yet — a titled display is the next step.

local ide = require("config.ide")

local M = {}

local BASE = 1 -- terminal 1 is the primary side terminal (<C-t>)
local MAX = 9

M.current = BASE -- id of the terminal currently shown

local function tterm()
  return require("toggleterm.terminal")
end

-- Our side terminals: vertical, ids 1..9, including hidden ones so a tab
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

-- Show terminal `id`, creating it if it doesn't exist yet. Any other managed
-- terminal occupying the slot is hidden (not killed) so it stays a tab.
function M.show(id)
  id = math.max(BASE, math.min(MAX, id))
  local existing = tterm().get(id, true)

  for _, t in ipairs(managed()) do
    if t.id ~= id and t:is_open() then
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
    require("toggleterm").toggle(id, ide.term_width(), nil, "vertical")
  end

  M.current = id
  vim.schedule(function()
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

-- Buffer-local tab keymaps for a terminal buffer (native backend). Normal-mode
-- only: enter terminal-normal (<C-\><C-n>, or the <C-n> map) then press <C-b>N.
-- Buffer-local so <C-b> keeps its default (page back) in every other buffer.
function M.setup_buffer_keymaps(bufnr)
  local map = vim.keymap.set
  for i = BASE, MAX do
    map("n", "<C-b>" .. i, function()
      M.show(i)
    end, { buffer = bufnr, desc = "Terminal tab " .. i })
  end
  map("n", "<C-b>c", M.new, { buffer = bufnr, desc = "New terminal tab" })
  map("n", "<C-b>r", M.repaint, { buffer = bufnr, desc = "Repaint terminal" })
end

-- Global toggle so <C-t> summons/hides the side terminal from anywhere.
-- Called once from terminal.lua.
function M.setup_keymaps()
  vim.keymap.set({ "n", "t" }, "<C-t>", M.toggle, { desc = "Toggle side terminal" })
end

return M
