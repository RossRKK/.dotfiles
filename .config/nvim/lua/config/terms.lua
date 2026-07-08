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
M.copymode = {} -- id -> true while that terminal is showing a frozen snapshot

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

-- ===================== copy mode (frozen snapshot) =====================
-- Live terminals yank the cursor to the bottom on every output frame, so you
-- can't read or scroll while output streams. Instead, whenever a managed
-- terminal enters terminal-normal mode we replace it in its window with a
-- frozen snapshot of its contents (an ordinary buffer) where normal/visual/
-- search/yank all work and nothing moves; entering insert mode in the snapshot
-- swaps the live terminal back. Driven entirely by ModeChanged (setup_copymode).

local snap_of = {} -- terminal id -> snapshot bufnr
local id_of_snap = {} -- snapshot bufnr -> terminal id

local function term_by_buf(buf)
  for _, t in ipairs(managed()) do
    if t.bufnr == buf then
      return t
    end
  end
end

local function snapshot_buf(id)
  local b = snap_of[id]
  if b and vim.api.nvim_buf_is_valid(b) then
    return b
  end
  b = vim.api.nvim_create_buf(false, true)
  vim.bo[b].buftype = "nofile"
  vim.bo[b].bufhidden = "hide"
  vim.bo[b].swapfile = false
  -- Same filetype as a toggleterm window so the width-enforcement autocmd and
  -- the tabline's term_col_width keep treating this window as the terminal slot.
  vim.bo[b].filetype = "toggleterm"
  pcall(vim.api.nvim_buf_set_name, b, "[copy " .. id .. "]")
  M.setup_buffer_keymaps(b) -- <C-b>{1-9}/c/r still switch tabs from the snapshot
  snap_of[id] = b
  id_of_snap[b] = id
  return b
end

-- Swap the live terminal for its snapshot in its window (enter copy mode).
function M.enter_copy(term)
  if M.copymode[term.id] then
    return
  end
  local win = (term.window and vim.api.nvim_win_is_valid(term.window)) and term.window
    or vim.api.nvim_get_current_win()
  local lines = vim.api.nvim_buf_get_lines(term.bufnr, 0, -1, false)
  local snap = snapshot_buf(term.id)
  vim.api.nvim_buf_set_lines(snap, 0, -1, false, lines)
  M.copymode[term.id] = true
  vim.api.nvim_win_set_buf(win, snap)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  -- Start at the bottom, where the terminal cursor was, then scroll up freely.
  pcall(vim.api.nvim_win_set_cursor, win, { vim.api.nvim_buf_line_count(snap), 0 })
  pcall(vim.cmd, "redrawtabline")
end

-- Swap the snapshot for its live terminal and resume terminal mode.
function M.exit_copy(id)
  if not M.copymode[id] then
    return
  end
  M.copymode[id] = nil
  local term = tterm().get(id, true)
  local snap = snap_of[id]
  local win
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if snap and vim.api.nvim_win_get_buf(w) == snap then
      win = w
      break
    end
  end
  win = win or (term and term.window)
  if term and win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(term.bufnr) then
    -- Leave the snapshot's insert mode first: swapping buffers mid-insert lands
    -- in terminal-normal and the startinsert below is a no-op (needing a second
    -- press). Drop to normal, swap, then enter terminal mode cleanly.
    vim.cmd("stopinsert")
    vim.api.nvim_win_set_buf(win, term.bufnr)
    vim.api.nvim_set_current_win(win)
    vim.cmd("startinsert")
  end
  pcall(vim.cmd, "redrawtabline")
end

-- Restore any snapshot windows to their live terminals without resuming insert
-- (used before switching/toggling tabs, so toggleterm sees its windows normally).
local function restore_all_copy()
  for id in pairs(M.copymode) do
    M.copymode[id] = nil
    local term = tterm().get(id, true)
    local snap = snap_of[id]
    if term and snap and vim.api.nvim_buf_is_valid(term.bufnr) then
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(w) == snap then
          vim.api.nvim_win_set_buf(w, term.bufnr)
        end
      end
    end
  end
end

-- Wire the mode-driven swapping (native only). Called once from terminal.lua.
-- Window/buffer swaps are deferred with vim.schedule so they don't run inside
-- the (text-locked) ModeChanged callback.
function M.setup_copymode()
  local grp = vim.api.nvim_create_augroup("TermCopyMode", { clear = true })
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = grp,
    pattern = "t:nt",
    callback = function()
      local term = term_by_buf(vim.api.nvim_get_current_buf())
      if term then
        vim.schedule(function()
          M.enter_copy(term)
        end)
      end
    end,
  })
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = grp,
    pattern = "*:i",
    callback = function()
      local id = id_of_snap[vim.api.nvim_get_current_buf()]
      if id and M.copymode[id] then
        vim.schedule(function()
          M.exit_copy(id)
        end)
      end
    end,
  })
end

-- Show terminal `id`, creating it if it doesn't exist yet. Any other managed
-- terminal occupying the slot is hidden (not killed) so it stays a tab.
function M.show(id)
  restore_all_copy()
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
    pcall(vim.cmd, "redrawtabline")
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
  restore_all_copy()
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

local function truncate(s, n)
  if vim.fn.strchars(s) > n then
    return vim.fn.strcharpart(s, 0, n - 1) .. "…"
  end
  return s
end

-- A tab's title: the OSC title the running program set (b:term_title — Claude
-- Code updates this live, including its input-needed marker), falling back to
-- the foreground process name from /proc, then "term".
local function label(id)
  local t = tterm().get(id, true)
  local name
  if t and t.bufnr and vim.api.nvim_buf_is_valid(t.bufnr) then
    local ok, title = pcall(function()
      return vim.b[t.bufnr].term_title
    end)
    if ok and type(title) == "string" and title ~= "" then
      name = title
    end
  end
  if not name then
    local pid, tpgid = term_procs(id)
    if pid then
      local target = (tpgid and tpgid > 0) and tpgid or pid
      local comm = read_file("/proc/" .. target .. "/comm")
      name = comm and (comm:gsub("%s+$", "")) or nil
    end
  end
  local marker = M.copymode[id] and "⧉ " or ""
  return string.format(" %d:%s%s ", id, marker, truncate(name or "term", 24))
end

-- Fit plain text to exactly w display columns (truncate with … or right-pad).
local function fit(s, w)
  if w <= 0 then
    return ""
  end
  local len = vim.fn.strchars(s)
  if len > w then
    return truncate(s, w)
  end
  return s .. string.rep(" ", w - len)
end

-- Live text width of the side terminal window (0 if it's currently hidden).
local function term_col_width()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local b = vim.api.nvim_win_get_buf(w)
    if vim.bo[b].filetype == "toggleterm" and vim.api.nvim_win_get_config(w).relative == "" then
      return vim.api.nvim_win_get_width(w)
    end
  end
  return 0
end

-- Name of the file in the main editor window (relative to cwd).
local function editor_bufname()
  local function is_editor(b)
    return vim.bo[b].buftype == "" and vim.bo[b].filetype ~= "NvimTree"
  end
  local function name_of(b)
    local n = vim.api.nvim_buf_get_name(b)
    return n == "" and "[No Name]" or vim.fn.fnamemodify(n, ":.")
  end
  local cur = vim.api.nvim_get_current_buf()
  if is_editor(cur) then
    return name_of(cur)
  end
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local b = vim.api.nvim_win_get_buf(w)
    if is_editor(b) then
      return name_of(b)
    end
  end
  return ""
end

-- Top bar aligned to the three windows: cwd over the explorer, the current file
-- over the editor, and the terminal tab strip over the terminal. Rendered in
-- nvim's top tabline (see M.enable_tabline) rather than a winbar on the terminal
-- window, so it doesn't steal a pty row / destabilise the terminal's rendering.
function M.tabline()
  local cols = vim.o.columns
  local tw = ide.tree_width() -- explorer region incl. its separator (0 if closed)
  local rw = term_col_width() -- terminal text region (0 if hidden)
  local mw = math.max(0, cols - tw - rw) -- editor region (incl. the term separator)

  local left = tw > 0 and fit(" " .. vim.fn.fnamemodify(vim.fn.getcwd(), ":~"), tw) or ""
  local mid = fit(" " .. editor_bufname(), mw)

  -- Terminal tabs, left-aligned in the terminal region, active one highlighted.
  local tabs, used = {}, 0
  if rw > 0 then
    for _, t in ipairs(managed()) do
      local lbl = label(t.id)
      used = used + vim.fn.strchars(lbl)
      local hl = (t.id == M.current) and "%#TabLineSel#" or "%#TabLine#"
      tabs[#tabs + 1] = string.format("%%%d@v:lua.__toggleterm_tab_click@%s%s%%X", t.id, hl, lbl)
    end
  end
  local right = table.concat(tabs)
  if used < rw then
    right = right .. "%#TabLineFill#" .. string.rep(" ", rw - used)
  end

  return "%#TabLine#" .. left .. "%#TabLineFill#" .. mid .. right
end

_G.__toggleterm_tabline = M.tabline
_G.__toggleterm_tab_click = function(id)
  M.show(id)
end

-- Turn on the top tab strip. term_title changes arrive via TermRequest (and the
-- constant redraws of a live terminal), so redraw the tabline on those.
function M.enable_tabline()
  vim.o.showtabline = 2
  vim.o.tabline = "%!v:lua.__toggleterm_tabline()"
  local grp = vim.api.nvim_create_augroup("TermTabline", { clear = true })
  vim.api.nvim_create_autocmd("TermRequest", {
    group = grp,
    callback = function()
      pcall(vim.cmd, "redrawtabline")
    end,
  })
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
