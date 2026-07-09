-- tmux-style tab switching for the vertical side terminal.
--
-- One terminal occupies the side slot at a time; the others stay alive but
-- hidden. Switching is done from terminal-normal mode (enter it with <C-\><C-n>,
-- or the <C-n> map): <C-b>{1-9} switches to (creating on demand) a terminal,
-- <C-b>c opens the next free slot, and <C-b>.{1-9} renumbers the current
-- terminal to another slot (tmux move-window). <C-t> toggles the side slot from
-- anywhere.
--
-- Slots (1..9) are ours; toggleterm's own terminal ids are opaque and never
-- shown or relied on. M.slots is the sole slot->Terminal mapping, so renumbering
-- is a swap in a table we own -- we never reach into toggleterm's internals.
-- Everything else here (copy mode, the tab strip) keys off the Terminal object.

local ide = require("config.ide")

local M = {}

local BASE = 1 -- slot 1 is the primary side terminal (<C-t>)
local MAX = 9

M.current = BASE -- slot currently shown
M.slots = {} -- slot (1..9) -> Terminal
M.copymode = {} -- Terminal -> true while it's showing a frozen snapshot

local function tterm()
  return require("toggleterm.terminal")
end

local function clamp(slot)
  return math.max(BASE, math.min(MAX, slot))
end

-- Our side terminals as a slot-ordered list of { slot, term } pairs, including
-- hidden ones so a tab persists after you switch away from it (tmux-window
-- semantics).
local function managed()
  local out = {}
  for slot, term in pairs(M.slots) do
    out[#out + 1] = { slot = slot, term = term }
  end
  table.sort(out, function(a, b)
    return a.slot < b.slot
  end)
  return out
end

local function open_managed()
  for _, e in ipairs(managed()) do
    if e.term:is_open() then
      return e.slot, e.term
    end
  end
end

local function slot_of_buf(buf)
  for _, e in ipairs(managed()) do
    if e.term.bufnr == buf then
      return e.slot, e.term
    end
  end
end

-- The slot/terminal a command should act on: the focused terminal (live buffer
-- or its copy-mode snapshot) if there is one, else whatever occupies the side slot.
local function current_target()
  local buf = vim.api.nvim_get_current_buf()
  local slot, term = slot_of_buf(buf)
  if slot then
    return slot, term
  end
  return open_managed()
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
local function term_procs(term)
  if not term or not term.job_id then
    return nil
  end
  local ok, pid = pcall(vim.fn.jobpid, term.job_id)
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

-- ===================== copy mode (frozen snapshot) =====================
-- Live terminals yank the cursor to the bottom on every output frame, so you
-- can't read or scroll while output streams. Copy mode (entered deliberately
-- with <C-b>[) replaces the terminal in its window with a frozen snapshot of
-- its contents (an ordinary buffer) where normal/visual/search/yank all work
-- and nothing moves; entering insert mode in the snapshot (i/a/q) swaps the
-- live terminal back.
--
-- Keyed by Terminal, not by slot: a snapshot belongs to its terminal and must
-- follow it through a renumber.

local snap_of = {} -- Terminal -> snapshot bufnr
local term_of_snap = {} -- snapshot bufnr -> Terminal

local function snapshot_buf(term)
  local b = snap_of[term]
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
  pcall(vim.api.nvim_buf_set_name, b, "[copy " .. tostring(term.bufnr) .. "]")
  -- Tab switching (<C-b>N) works here via the global prefix map (see setup_keymaps).
  -- Resume the live terminal directly: keys that would start insert (plus q) drop
  -- copy mode in one press, instead of first entering the snapshot's own insert
  -- mode and having exit_copy react to it (which needed a second press).
  for _, k in ipairs({ "i", "a", "I", "A", "q" }) do
    vim.keymap.set("n", k, function()
      M.exit_copy(term)
    end, { buffer = b, desc = "Resume terminal (leave copy mode)" })
  end
  snap_of[term] = b
  term_of_snap[b] = term
  return b
end

-- <C-b>[: deliberately enter copy mode on the focused terminal (or, if <C-b>
-- was pressed from the editor, the open side terminal).
function M.enter_copy_current()
  local _, term = current_target()
  if term then
    M.enter_copy(term)
  end
end

-- Swap the live terminal for its snapshot in its window (enter copy mode).
function M.enter_copy(term)
  if M.copymode[term] then
    return
  end
  local win = (term.window and vim.api.nvim_win_is_valid(term.window)) and term.window
    or vim.api.nvim_get_current_win()
  -- Remember the live terminal's full view -- scroll position (topline) as well
  -- as the cursor -- so the snapshot opens showing exactly the same lines. Setting
  -- only the cursor makes nvim recenter and the content visibly jumps. The buffers
  -- share content, so the saved view maps across unchanged.
  local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
  local lines = vim.api.nvim_buf_get_lines(term.bufnr, 0, -1, false)
  local snap = snapshot_buf(term)
  vim.api.nvim_buf_set_lines(snap, 0, -1, false, lines)
  M.copymode[term] = true
  vim.api.nvim_win_set_buf(win, snap)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  pcall(vim.api.nvim_win_call, win, function()
    vim.fn.winrestview(view) -- winrestview clamps lnum to the buffer itself
  end)
  pcall(vim.cmd, "redrawtabline")
end

-- Swap the snapshot for its live terminal, landing in terminal-normal mode --
-- the mode the terminal was in when copy mode took over. Press i to type.
function M.exit_copy(term)
  if not M.copymode[term] then
    return
  end
  M.copymode[term] = nil
  local snap = snap_of[term]
  local win
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if snap and vim.api.nvim_win_get_buf(w) == snap then
      win = w
      break
    end
  end
  win = win or term.window
  if win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(term.bufnr) then
    -- If we arrived via the *:i autocmd (insert started in the snapshot), drop
    -- that insert first so the swap lands cleanly in terminal-normal.
    vim.cmd("stopinsert")
    vim.api.nvim_win_set_buf(win, term.bufnr)
    vim.api.nvim_set_current_win(win)
  end
  pcall(vim.cmd, "redrawtabline")
end

-- Restore any snapshot windows to their live terminals without resuming insert
-- (used before switching/toggling tabs, so toggleterm sees its windows normally).
local function restore_all_copy()
  for term in pairs(M.copymode) do
    M.copymode[term] = nil
    local snap = snap_of[term]
    if snap and vim.api.nvim_buf_is_valid(term.bufnr) then
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(w) == snap then
          vim.api.nvim_win_set_buf(w, term.bufnr)
        end
      end
    end
  end
end

-- Forget a terminal's copy-mode state (its shell exited; the snapshot is dead).
local function forget_copy(term)
  local snap = snap_of[term]
  if snap then
    term_of_snap[snap] = nil
    if vim.api.nvim_buf_is_valid(snap) then
      pcall(vim.api.nvim_buf_delete, snap, { force = true })
    end
  end
  snap_of[term] = nil
  M.copymode[term] = nil
end

-- Wire copy mode's exit trigger. Called once from terminal.lua.
-- Entry is deliberate now (<C-b>[ -> enter_copy_current); the only mode-driven
-- part left is leaving -- entering insert in the snapshot swaps the live
-- terminal back. The vim.schedule keeps the swap out of the (text-locked)
-- ModeChanged callback.
function M.setup_copymode()
  local grp = vim.api.nvim_create_augroup("TermCopyMode", { clear = true })
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = grp,
    pattern = "*:i",
    callback = function()
      local term = term_of_snap[vim.api.nvim_get_current_buf()]
      if term and M.copymode[term] then
        vim.schedule(function()
          M.exit_copy(term)
        end)
      end
    end,
  })
end

-- Show the terminal in `slot`, creating it if the slot is empty. Any other
-- managed terminal occupying the side slot is hidden (not killed) so it stays a
-- tab. `opts.insert` (default true) controls whether we land in terminal mode.
function M.show(slot, opts)
  opts = opts or {}
  restore_all_copy()
  slot = clamp(slot)

  for _, e in ipairs(managed()) do
    if e.slot ~= slot and e.term:is_open() then
      e.term:close()
    end
  end

  local term = M.slots[slot]
  if not term then
    -- No count/id: toggleterm assigns an opaque one. direction, shell, on_open
    -- (winfixwidth, width, <C-k> passthrough) all come from the global config.
    term = tterm().Terminal:new({ direction = "vertical" })
    M.slots[slot] = term
  end

  if term:is_open() then
    if term.window and vim.api.nvim_win_is_valid(term.window) then
      vim.api.nvim_set_current_win(term.window)
    end
  else
    term:open(ide.term_width(), "vertical")
  end

  M.current = slot
  vim.schedule(function()
    pcall(vim.cmd, "redrawtabline")
    if opts.insert ~= false then
      vim.cmd("startinsert")
    end
  end)
end

-- <C-t>: toggle the side slot — hide it if open, else re-show the current tab.
function M.toggle()
  restore_all_copy()
  local _, open = open_managed()
  if open then
    open:close()
  else
    M.show(M.current or BASE)
  end
end

-- <C-b>c: open the lowest unused slot.
function M.new()
  for i = BASE, MAX do
    if not M.slots[i] then
      M.show(i)
      return
    end
  end
  vim.notify("all " .. MAX .. " terminal slots in use", vim.log.levels.WARN)
end

-- <C-b>.{1-9}: renumber the shown side terminal to `dest` (tmux move-window).
-- If `dest` is occupied the two terminals swap slots so neither is clobbered;
-- otherwise the source slot is freed. The shown window/buffer are untouched --
-- only the slot (hence tab label and switch key) changes. Purely a swap in
-- M.slots: toggleterm's own ids are opaque and stay put.
function M.move(dest)
  restore_all_copy()
  dest = clamp(dest)
  local source, term = current_target()
  if not term or source == dest then
    return
  end
  M.slots[source], M.slots[dest] = M.slots[dest], term
  M.current = dest
  vim.schedule(function()
    pcall(vim.cmd, "redrawtabline")
  end)
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
local function label(slot, term)
  local name
  if term.bufnr and vim.api.nvim_buf_is_valid(term.bufnr) then
    local ok, title = pcall(function()
      return vim.b[term.bufnr].term_title
    end)
    if ok and type(title) == "string" and title ~= "" then
      name = title
    end
  end
  if not name then
    local pid, tpgid = term_procs(term)
    if pid then
      local target = (tpgid and tpgid > 0) and tpgid or pid
      local comm = read_file("/proc/" .. target .. "/comm")
      name = comm and (comm:gsub("%s+$", "")) or nil
    end
  end
  local marker = M.copymode[term] and "⧉ " or ""
  return string.format(" %d:%s%s ", slot, marker, truncate(name or "term", 24))
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
    for _, e in ipairs(managed()) do
      local lbl = label(e.slot, e.term)
      used = used + vim.fn.strchars(lbl)
      local hl = (e.slot == M.current) and "%#TabLineSel#" or "%#TabLine#"
      tabs[#tabs + 1] = string.format("%%%d@v:lua.__toggleterm_tab_click@%s%s%%X", e.slot, hl, lbl)
    end
  end
  local right = table.concat(tabs)
  if used < rw then
    right = right .. "%#TabLineFill#" .. string.rep(" ", rw - used)
  end

  return "%#TabLine#" .. left .. "%#TabLineFill#" .. mid .. right
end

_G.__toggleterm_tabline = M.tabline
_G.__toggleterm_tab_click = function(slot)
  -- Defer so nvim's own mouse-click/window handling finishes before we juggle
  -- terminal windows (a synchronous show() here races it and scrambles the layout).
  vim.schedule(function()
    M.show(slot)
  end)
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

-- Global toggle so <C-t> summons/hides the side terminal from anywhere.
-- Called once from terminal.lua.
function M.setup_keymaps()
  vim.keymap.set({ "n", "t" }, "<C-t>", M.toggle, { desc = "Toggle side terminal" })
  -- <C-b> as a single tmux-style prefix, bound globally in normal + terminal
  -- mode. A single complete mapping fires immediately, then getcharstr() blocks
  -- for the follow-up key. Separate <C-b>1.. maps instead race the mapping
  -- timeout in terminal mode -- a digit pressed a beat late leaks to the shell.
  -- Global so it works from the live terminal, the copy-mode snapshot, and the
  -- editor (to summon a tab when the panel is closed). Trade-off accepted: <C-b>
  -- no longer pages back in normal-mode buffers.
  local function tab_prefix()
    local ok, key = pcall(vim.fn.getcharstr)
    if not ok or key == "" then
      return
    end
    if key:match("^[1-9]$") then
      M.show(tonumber(key))
    elseif key == "c" then
      M.new()
    elseif key == "[" then
      M.enter_copy_current()
    elseif key == "." then
      -- tmux move-window: the next keystroke is the destination slot.
      local ok2, dest = pcall(vim.fn.getcharstr)
      if ok2 and dest:match("^[1-9]$") then
        M.move(tonumber(dest))
      end
    end
  end
  vim.keymap.set(
    { "n", "t" },
    "<C-b>",
    tab_prefix,
    { desc = "Terminal prefix (<C-b>N tab / <C-b>c new / <C-b>. move / <C-b>[ copy)" }
  )
  vim.keymap.set(
    { "n", "t" },
    "<C-t>",
    tab_prefix,
    { desc = "Terminal prefix (<C-t>N tab / <C-b>c new / <C-b>. move / <C-b>[ copy)" }
  )
end

-- When a managed terminal's shell exits, free its slot and show another open tab
-- if one remains; if it was the last, the side panel just closes. Called once
-- from terminal.lua.
function M.setup_exit()
  vim.api.nvim_create_autocmd("TermClose", {
    group = vim.api.nvim_create_augroup("TermExit", { clear = true }),
    callback = function(args)
      local slot, term = slot_of_buf(args.buf)
      if not slot then
        return
      end
      M.slots[slot] = nil
      forget_copy(term)
      -- Deferred: let toggleterm finish closing the exited terminal's window
      -- before we swap another managed terminal into the side slot.
      vim.schedule(function()
        for _, e in ipairs(managed()) do
          if vim.api.nvim_buf_is_valid(e.term.bufnr) then
            M.show(e.slot)
            return
          end
        end
      end)
    end,
  })
end

return M
