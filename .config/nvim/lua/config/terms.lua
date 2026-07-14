-- tmux-style tab switching for the vertical side terminal.
--
-- One terminal occupies the side slot at a time; the others stay alive but
-- hidden. Switching is done from terminal-normal mode (enter it with <C-\><C-n>,
-- or the <C-n> map): <C-b>{1-9} switches to (creating on demand) a terminal,
-- <C-b>c opens the next free slot, <C-b>& kills the current terminal (tmux
-- kill-window), and <C-b>.{1-9} renumbers the current terminal to another slot
-- (tmux move-window). <C-t> toggles the side slot from anywhere.
--
-- Slots (1..9) are ours. M.slots is the sole slot->terminal mapping (each value
-- a Snacks.win we created with snacks.terminal.open), so renumbering is a swap in
-- a table we own -- we never rely on snacks' own cmd-keyed terminal cache.
-- Everything else here (the tab strip) keys off the Snacks.win object.

local M = {}

local BASE = 1 -- slot 1 is the primary side terminal (<C-t>)
local MAX = 9

M.current = BASE -- slot currently shown
M.slots = {} -- slot (1..9) -> Terminal

local function snacks_term()
  return require("snacks.terminal")
end

-- Create a fresh side terminal. We hold the returned Snacks.win in M.slots
-- ourselves and drive it with show()/hide(); snacks' own cmd-keyed cache is
-- bypassed via .open() (a brand-new instance every call), so all nine slots stay
-- independent even though they share cmd/cwd. interactive = false keeps snacks
-- from auto-inserting or popping an error notify when kill() tears a shell down.
-- Placement and sizing (right edge) are edgy's job -- see lua/plugins/edgy.lua.
local function new_side_term()
  return snacks_term().open(nil, {
    interactive = false,
    win = {
      position = "right",
      -- Runs at the end of Snacks.win:show().
      on_win = function(self)
        -- Suppress snacks' per-window winbar (it defaults to "id: term_title" for
        -- split terminals); config/terms.lua's top tab strip already titles this
        -- region, and edgy's own title is disabled for it too.
        vim.wo[self.win].winbar = ""
        -- The side terminal is full-height (nothing above it), so <C-k> nav is
        -- useless here; pass it through to the running app (e.g. Claude Code).
        vim.keymap.set("t", "<C-k>", "<C-k>", { buffer = self.buf })
      end,
    },
  })
end

-- Kill a terminal's shell. Snacks' win:close() never wipes a live terminal
-- buffer, so delete the buffer directly: that stops the job and fires TermClose,
-- which setup_exit uses to free the slot and surface another tab.
local function shutdown(term)
  if term.buf and vim.api.nvim_buf_is_valid(term.buf) then
    vim.api.nvim_buf_delete(term.buf, { force = true })
  end
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
    if e.term:win_valid() then
      return e.slot, e.term
    end
  end
end

local function slot_of_buf(buf)
  for _, e in ipairs(managed()) do
    if e.term.buf == buf then
      return e.slot, e.term
    end
  end
end

-- The slot/terminal a command should act on: the focused terminal if there is
-- one, else whatever occupies the side slot.
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
  if not term or not term.buf or not vim.api.nvim_buf_is_valid(term.buf) then
    return nil
  end
  -- The terminal's job id lives on the buffer (set by termopen), not on the
  -- Snacks.win object.
  local ok, jid = pcall(function()
    return vim.b[term.buf].terminal_job_id
  end)
  if not ok or type(jid) ~= "number" then
    return nil
  end
  local ok2, pid = pcall(vim.fn.jobpid, jid)
  if not ok2 or type(pid) ~= "number" then
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

-- Show the terminal in `slot`, creating it if the slot is empty. Any other
-- managed terminal occupying the side slot is hidden (not killed) so it stays a
-- tab. `opts.insert` (default true) controls whether we land in terminal mode.
function M.show(slot, opts)
  opts = opts or {}
  slot = clamp(slot)

  for _, e in ipairs(managed()) do
    if e.slot ~= slot and e.term:win_valid() then
      e.term:hide()
    end
  end

  local term = M.slots[slot]
  if not term then
    -- new_side_term() opens the split immediately (position, width, on_win all
    -- baked into its opts), so the freshly created terminal is already shown.
    term = new_side_term()
    M.slots[slot] = term
  end

  if term:win_valid() then
    if term.win and vim.api.nvim_win_is_valid(term.win) then
      vim.api.nvim_set_current_win(term.win)
    end
  else
    term:show()
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
  local _, open = open_managed()
  if open then
    open:hide()
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

-- <C-b>&: kill the current side terminal (tmux kill-window). Unlike <C-t>, which
-- only hides the tab, this shuts the shell down; the TermClose handler
-- (setup_exit) then frees the slot and shows another open tab if one remains.
function M.kill()
  local _, term = current_target()
  if term then
    shutdown(term)
  end
end

-- <C-b>.{1-9}: renumber the shown side terminal to `dest` (tmux move-window).
-- If `dest` is occupied the two terminals swap slots so neither is clobbered;
-- otherwise the source slot is freed. The shown window/buffer are untouched --
-- only the slot (hence tab label and switch key) changes. Purely a swap in
-- M.slots; snacks' own terminal cache is never consulted, so ids can't drift.
function M.move(dest)
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
  if term.buf and vim.api.nvim_buf_is_valid(term.buf) then
    local ok, title = pcall(function()
      return vim.b[term.buf].term_title
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
  return string.format(" %d:%s ", slot, truncate(name or "term", 24))
end

-- Live text width of the side terminal window (0 if it's currently hidden).
local function term_col_width()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local b = vim.api.nvim_win_get_buf(w)
    if vim.bo[b].filetype == "snacks_terminal" and vim.api.nvim_win_get_config(w).relative == "" then
      return vim.api.nvim_win_get_width(w)
    end
  end
  return 0
end

-- Top bar carrying just the terminal tab strip, right-aligned over the terminal
-- region (edgy's right edgebar). The explorer and editor regions are left blank
-- here -- their titles come from edgy's panel bars and the winbar. Rendered in
-- nvim's top tabline (see M.enable_tabline) rather than a winbar on the terminal
-- window, so it doesn't steal a pty row / destabilise the terminal's rendering.
function M.tabline()
  local cols = vim.o.columns
  local rw = term_col_width() -- terminal text region (0 if hidden)

  -- Terminal tabs, left-aligned within the terminal region, active one highlighted.
  local tabs, used = {}, 0
  if rw > 0 then
    for _, e in ipairs(managed()) do
      local lbl = label(e.slot, e.term)
      used = used + vim.fn.strchars(lbl)
      local hl = (e.slot == M.current) and "%#TabLineSel#" or "%#TabLine#"
      tabs[#tabs + 1] = string.format("%%%d@v:lua.__snacks_term_tab_click@%s%s%%X", e.slot, hl, lbl)
    end
  end
  local strip = table.concat(tabs)
  if used < rw then
    strip = strip .. "%#TabLineFill#" .. string.rep(" ", rw - used)
  end

  -- Pad the editor+explorer region (everything left of the terminal) with blank.
  local pad = math.max(0, cols - rw)
  return "%#TabLineFill#" .. string.rep(" ", pad) .. strip
end

_G.__snacks_term_tabline = M.tabline
_G.__snacks_term_tab_click = function(slot)
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
  vim.o.tabline = "%!v:lua.__snacks_term_tabline()"
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
  -- Global so it works from the live terminal and the editor (to summon a tab
  -- when the panel is closed). Trade-off accepted: <C-b>
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
    elseif key == "&" then
      M.kill()
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
    { desc = "Terminal prefix (<C-b>N tab / <C-b>c new / <C-b>& kill / <C-b>. move)" }
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
      -- Deferred: let snacks finish closing the exited terminal's window
      -- before we swap another managed terminal into the side slot.
      vim.schedule(function()
        for _, e in ipairs(managed()) do
          if vim.api.nvim_buf_is_valid(e.term.buf) then
            M.show(e.slot)
            return
          end
        end
      end)
    end,
  })
end

return M
