-- Workspaces: one project per nvim tabpage.
--
-- A workspace tabpage is the IDE layout (explorer left, side terminal
-- right, editor in the middle) rooted at a project directory. Opening a second
-- one gives you a second project side by side, without a second nvim. Each
-- workspace gets a stable number (M.slot), shown on its tab label: <M-N>
-- switches to it from any mode, terminal included. gt/gT and the picker below
-- still work.
--
-- The pieces this rests on are all already per-tabpage: edgy's layout, neo-tree's
-- state, fishmonger's terminal slots (each tab gets its own 1..9, spawned in that
-- tab's cwd), and config.windows' main-window routing. What is NOT per-tabpage is
-- the buffer list -- Vim buffers are global -- so plugins/buffers.lua filters the
-- bufferline by the tab's cwd to keep <S-l>/<S-h> within one project.
--
-- Startup (`nvim <dir>`, see config.ide) builds the first workspace through the
-- same open() the picker uses, so there is one definition of the layout.

local M = {}

---@class workspace.Options
---@field agent_worktrees boolean worktrees are named after their agent (util/worktree.lua)
local options = { agent_worktrees = false }

local name_parts, join_name, label_prefix, tab_label, labels_width

--- Set once at startup, from the environment (init.lua).
---@param opts workspace.Options
function M.setup(opts)
  options = vim.tbl_extend("force", options, opts)
end

--- The name of a tabpage's workspace: the basename of its cwd. Set as a
--- tab-local variable at open() so it survives a later :tcd and so the picker
--- doesn't have to re-derive it.
---@param tab? integer tabpage handle (default: current)
---@return string
function M.name(tab)
  tab = tab or vim.api.nvim_get_current_tabpage()
  local ok, name = pcall(vim.api.nvim_tabpage_get_var, tab, "workspace")
  if ok and type(name) == "string" and name ~= "" then
    return name
  end
  return vim.fn.fnamemodify(M.cwd(tab), ":t")
end

--- What a workspace is called wherever it's on display -- the tab labels, and
--- fishmonger's agent view (via project_name in plugins/fishmonger.lua) -- so
--- both agree.
---
--- "<repo> - <branch>", so a worktree reads as the repo and the
--- branch it holds (myrepo/.worktrees/rkk-some-branch -> "myrepo -
--- rkk/some-branch") rather than as its checkout directory. Drawn from the
--- greeter's cached branch report (config.greeter fetches one per workspace
--- and watches the git dirs, so it follows checkouts); before the report lands
--- -- or for a directory git can't say anything about -- it falls back to the
--- plain workspace name.
---@param tab? integer tabpage handle (default: current)
---@return string
function M.display_name(tab)
  return join_name(name_parts(tab or vim.api.nvim_get_current_tabpage()), {})
end

---@alias workspace.NamePart "repo"|"agent"|"branch"|"workspace"

---@class workspace.Name
---@field parts { part: workspace.NamePart, text: string }[]
---@field sep string

--- A workspace's display name as the parts a tab label can shed.
---@param tab integer tabpage handle
---@return workspace.Name
function name_parts(tab)
  local cwd = vim.fs.normalize(M.cwd(tab))
  -- package.loaded, not require: no reason to drag the greeter in just to name
  -- a tab, and before its setup there is no report to read anyway.
  local greeter = package.loaded["config.greeter"]
  local report = greeter and greeter.reports[cwd]
  if not (report and report.repo) then
    return { parts = { { part = "workspace", text = M.name(tab) } }, sep = "" }
  end
  local parts = { { part = "repo", text = report.repo } }
  -- An agent worktree is named after its agent, and the branch is whatever it has out now.
  local agent = options.agent_worktrees and report.git_dir ~= report.common_dir
  if agent then
    parts[#parts + 1] = { part = "agent", text = vim.fs.basename(cwd) }
  end
  local branch = report.branch or report.head
  if branch then
    parts[#parts + 1] = { part = "branch", text = branch }
  end
  return { parts = parts, sep = agent and " · " or " - " }
end

--- The name without the `dropped` parts, or whole if that would leave nothing.
---@param name workspace.Name
---@param dropped table<workspace.NamePart, true>
---@return string
function join_name(name, dropped)
  local kept = {}
  for _, p in ipairs(name.parts) do
    if not dropped[p.part] then
      kept[#kept + 1] = p.text
    end
  end
  return #kept > 0 and table.concat(kept, name.sep) or join_name(name, {})
end

--- A workspace's number: the key that reaches it (<M-N>, and fishmonger's
--- <C-b>mN to send a terminal there), shown on its tab label. Stable the way
--- fishmonger's terminal slots are: a workspace keeps its number for life, a
--- new one takes the lowest free number, and closing one leaves a gap rather
--- than renumbering the rest -- unlike the tabpage number, which shifts under
--- every workspace to the right of a closed one, so a key learned for a
--- project would start reaching a different one. Nil for a tabpage that isn't
--- a workspace (the dap debug tab).
---@param tab? integer tabpage handle (default: current)
---@return integer?
function M.slot(tab)
  local ok, n = pcall(vim.api.nvim_tabpage_get_var, tab or 0, "workspace_slot")
  return ok and type(n) == "number" and n or nil
end

--- The workspace tabpage numbered `n`, or nil if no workspace has it.
---@param n integer
---@return integer?
function M.tab(n)
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if M.slot(tab) == n then
      return tab
    end
  end
end

--- Number the CURRENT tabpage as a workspace unless it already has one --
--- `want` if that is free (<M-N> on an empty number opens the workspace AS
--- number N), else the lowest free number -- and move it into number order so
--- the tab strip reads left to right in the order of the keys. Only the new tabpage moves, and
--- only if it is out of order: the others already are, and a non-workspace
--- tabpage (the dap debug tab) stays wherever it was opened.
---@param want? integer
function M.assign_slot(want)
  local tab = vim.api.nvim_get_current_tabpage()
  if M.slot(tab) then
    return
  end
  local n = want
  if not n or M.tab(n) then
    n = 1
    while M.tab(n) do
      n = n + 1
    end
  end
  vim.api.nvim_tabpage_set_var(tab, "workspace_slot", n)
  -- In order means after the last workspace numbered below this one (`lo`)
  -- and before the first numbered above it (`hi`).
  local lo, hi = 0, math.huge
  for nr, other in ipairs(vim.api.nvim_list_tabpages()) do
    local s = M.slot(other)
    if other ~= tab and s then
      if s < n then
        lo = nr
      elseif nr < hi then
        hi = nr
      end
    end
  end
  local here = vim.api.nvim_tabpage_get_number(tab)
  if here < lo or here > hi then
    -- :tabmove N puts the current tabpage after the one at position N (0 =
    -- first).
    vim.cmd("tabmove " .. lo)
  end
end

--- Switch to workspace `n` (<M-N>), or open one there: an empty number brings
--- up the project picker, and what you pick becomes workspace `n` -- the way
--- fishmonger's <C-b>N creates the terminal in an empty slot. Lands in
--- terminal mode when the window
--- you land on is a terminal: the switch is mostly made from one (the
--- binding works in terminal mode for that reason), and leaving the window
--- drops you out of terminal mode, so landing in terminal-normal would cost
--- an `i` on every switch.
---@param n integer
function M.switch(n)
  local tab = M.tab(n)
  if not tab then
    M.pick_new({ tab = true, slot = n })
    return
  end
  if tab == vim.api.nvim_get_current_tabpage() then
    return
  end
  vim.api.nvim_set_current_tabpage(tab)
  vim.schedule(function()
    if vim.bo.buftype == "terminal" then
      vim.cmd("startinsert")
    end
  end)
end

--- Put the workspace tabpages back in number order, left to right, after a
--- renumber. Done with autocmds off: it hops through tabpages only to move
--- them, and every hop would otherwise relabel, refresh greeters and repaint
--- the title for a tabpage you never actually visit. Non-workspace tabpages
--- end up after the workspaces.
local function sort_tabs()
  local current = vim.api.nvim_get_current_tabpage()
  local ordered = {}
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if M.slot(tab) then
      ordered[#ordered + 1] = tab
    end
  end
  table.sort(ordered, function(a, b)
    return M.slot(a) < M.slot(b)
  end)
  for i, tab in ipairs(ordered) do
    local anchor = i == 1 and 0 or vim.api.nvim_tabpage_get_number(ordered[i - 1])
    if vim.api.nvim_tabpage_get_number(tab) ~= anchor + 1 then
      vim.cmd("noautocmd tabnext " .. vim.api.nvim_tabpage_get_number(tab))
      vim.cmd("noautocmd tabmove " .. anchor)
    end
  end
  vim.cmd("noautocmd tabnext " .. vim.api.nvim_tabpage_get_number(current))
end

--- Renumber the current workspace to `n` (<M-b>.N), the way fishmonger's
--- <C-b>.N renumbers a terminal: if `n` is taken the two workspaces swap
--- numbers, so neither is lost. The tab strip follows, so it stays in key
--- order.
---@param n integer
function M.renumber(n)
  local tab = vim.api.nvim_get_current_tabpage()
  local from = M.slot(tab)
  if not from or from == n then
    return
  end
  local other = M.tab(n)
  if other then
    vim.api.nvim_tabpage_set_var(other, "workspace_slot", from)
  end
  vim.api.nvim_tabpage_set_var(tab, "workspace_slot", n)
  sort_tabs()
  M.set_labels()
  -- The OS title (plugins/fishmonger.lua) shows the numbers too.
  vim.api.nvim_exec_autocmds("User", { pattern = "WorkspaceRenumbered" })
end

--- Close the current workspace (<M-b>&, <leader>tx) and with it its
--- terminals. Asks first when one of them holds an agent that is working or
--- waiting on you -- the one case where a slip throws away work in flight.
--- A finished agent ("done") or a plain shell closes on the keypress.
function M.close()
  local live = M.live_agents(vim.api.nvim_get_current_tabpage())
  if live > 0 then
    local msg = ("Close %s? %d agent%s still working or waiting."):format(
      M.display_name(),
      live,
      live == 1 and " is" or "s are"
    )
    if vim.fn.confirm(msg, "&Close\n&Cancel", 2) ~= 1 then
      return
    end
  end
  local ok = pcall(vim.cmd, "tabclose")
  if not ok then
    vim.notify("can't close the last workspace", vim.log.levels.WARN)
  end
end

--- How many of a tabpage's terminals hold an agent that is working or waiting on you.
---@param tab integer tabpage handle
---@return integer
function M.live_agents(tab)
  local fishmonger = package.loaded["fishmonger"]
  local live = 0
  for _, term in ipairs(fishmonger and fishmonger.tabs(tab) or {}) do
    if term.agent and term.agent.state ~= "done" then
      live = live + 1
    end
  end
  return live
end

--- <M-b>: the workspace prefix, fishmonger's <C-b> with a different modifier
--- and the same keys -- N switches (or opens into N), c opens a new one, &
--- closes this one, .N renumbers it. Plus the other ways in, numbered as c
--- is: w opens a branch's worktree (util/worktree.lua), b names a new branch
--- for one (w's typed-name fallback only fires when nothing fuzzy-matches,
--- which a ticket name nearly always does), e a browsed-to
--- directory for a project the recent list doesn't know (a fresh clone). One
--- mapping that then reads the next key (as fishmonger's prefix does) rather
--- than separate <M-b>N maps, which race
--- the mapping timeout in terminal mode and leak a late key to the shell.
function M.prefix()
  local ok, key = pcall(vim.fn.getcharstr)
  if not ok then
    return
  end
  if key:match("^[1-9]$") then
    M.switch(tonumber(key))
  elseif key == "c" then
    M.pick_new()
  elseif key == "w" then
    require("util.worktree").pick()
  elseif key == "b" then
    require("util.worktree").new()
  elseif key == "e" then
    M.explore()
  elseif key == "&" then
    M.close()
  elseif key == "." then
    local ok2, dest = pcall(vim.fn.getcharstr)
    if ok2 and dest:match("^[1-9]$") then
      M.renumber(tonumber(dest))
    end
  end
end

--- A tabpage's working directory (its tab-local cwd, else the global one).
---@param tab? integer tabpage handle (default: current)
---@return string
function M.cwd(tab)
  tab = tab or vim.api.nvim_get_current_tabpage()
  local nr = vim.api.nvim_tabpage_get_number(tab)
  return vim.fn.getcwd(-1, nr)
end

-- Short highlight names for the tab-strip status glyphs. bufferline reserves
-- width for a tab by measuring the raw `t:name` string, %-codes and all, so
-- every character of a group name inside the label narrows the buffer section
-- of the bar -- hence FmT1/FmT1S rather than the state group's own name.
local glyph_groups = {}

--- The tabline highlight code for a status glyph: the agent state's colour
--- (fishmonger's hl, e.g. DiagnosticWarn) over the tab tile's own background,
--- which differs between the selected tile and the rest. Re-derived on every
--- call rather than cached: it follows colorscheme changes and bufferline
--- setting its groups up late (VeryLazy) for free, and set_labels runs on events
--- (an agent or title change, a tabpage switch), never on a timer.
---@param hl string highlight group carrying the state's fg
---@param selected boolean is this the current tabpage's tile
---@return string
local function glyph_code(hl, selected)
  local id = glyph_groups[hl]
  if not id then
    id = tostring(vim.tbl_count(glyph_groups) + 1)
    glyph_groups[hl] = id
  end
  local name = "FmT" .. id .. (selected and "S" or "")
  local tile = selected and "BufferLineTabSelected" or "BufferLineTab"
  vim.api.nvim_set_hl(0, name, {
    fg = vim.api.nvim_get_hl(0, { name = hl, link = false }).fg,
    bg = vim.api.nvim_get_hl(0, { name = tile, link = false }).bg,
  })
  return "%#" .. name .. "#"
end

--- The code that hands the rest of the label back to the tile's own highlight
--- after a coloured glyph. An alias of the bufferline group rather than the
--- group itself, purely to keep the label short (see glyph_groups).
---@param selected boolean
---@return string
local function restore_code(selected)
  local name = selected and "FmT0S" or "FmT0"
  vim.api.nvim_set_hl(0, name, { link = selected and "BufferLineTabSelected" or "BufferLineTab" })
  return "%#" .. name .. "#"
end

-- What every tab label sheds, first to last, until the strip fits the screen.
local drop_order = { "repo" } ---@type workspace.NamePart[]

-- bufferline frames each tab name in a padding cell and a separator either side.
local tab_frame_width = 4

--- Paint every tabpage's label on the bufferline's tab indicators: the project name,
--- prefixed with the status glyph of each of that tabpage's side terminals, in
--- that state's colour -- the same icon and highlight the agent view and the
--- greeter's Agents section use (fishmonger resolves the hook-reported agent
--- state first, falling back to the leading glyph of the terminal's OSC title).
--- That's the point of the glyphs being here rather than only in the OS title: a
--- background project whose agent is waiting on you says so from its tab -- and
--- says so in orange -- without switching to it.
---
--- bufferline renders a tabpage as `t:name` (falling back to the tab number)
--- without escaping it, which is what lets the %#..# codes through; it also
--- means they must be re-picked when the current tabpage changes, since the
--- glyph sits on the selected tile's background or an ordinary one. The
--- TabEnter hook in plugins/fishmonger.lua repaints every label for that.
---
--- All at once because the labels share the width: when they overflow
--- `columns`, every tab drops the same parts (drop_order), so they read alike.
function M.set_labels()
  local current = vim.api.nvim_get_current_tabpage()
  local tabs = {}
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    tabs[#tabs + 1] =
      { tab = tab, prefix = label_prefix(tab, tab == current), name = name_parts(tab) }
  end
  local dropped = {}
  for _, part in ipairs(drop_order) do
    if labels_width(tabs, dropped) <= vim.o.columns then
      break
    end
    dropped[part] = true
  end
  for _, t in ipairs(tabs) do
    vim.api.nvim_tabpage_set_var(t.tab, "name", tab_label(t, dropped))
  end
  -- Coalesced: an agent change relabels every tabpage, and one redraw shows
  -- all of them -- per-call redraws re-evaluated the whole bufferline per tab.
  if not M._redraw_queued then
    M._redraw_queued = true
    vim.schedule(function()
      M._redraw_queued = false
      pcall(vim.cmd, "redrawtabline")
    end)
  end
end

---@class workspace.TabLabel
---@field tab integer
---@field prefix string the number and status glyphs, already tabline-escaped
---@field name workspace.Name

--- A tabpage's number and its side terminals' status glyphs, ready for the name.
---@param tab integer
---@param selected boolean is this the current tabpage's tile
---@return string
function label_prefix(tab, selected)
  local fishmonger = package.loaded["fishmonger"]
  local icons, coloured = {}, false
  if fishmonger then
    -- Each glyph's cell ends in its padding, which also parts the last from the name.
    local glyph_cell = require("fishmonger.agent").glyph_cell
    for _, term in ipairs(fishmonger.tabs(tab)) do
      if term.icon and term.hl then
        coloured = true
        icons[#icons + 1] = glyph_code(term.hl, selected) .. glyph_cell(term.icon)
      elseif term.icon then
        icons[#icons + 1] = glyph_cell(term.icon)
      end
    end
  end
  local glyphs = table.concat(icons) .. (coloured and restore_code(selected) or "")
  -- The number first, where it lines up with the key that reaches it (<M-N>).
  local slot = M.slot(tab)
  return slot and (slot .. " " .. glyphs) or glyphs
end

--- A tab's label with the `dropped` parts of its name left out.
---@param t workspace.TabLabel
---@param dropped table<workspace.NamePart, true>
---@return string
function tab_label(t, dropped)
  -- Escaped because the label lands in the tabline as-is: a directory with a
  -- literal % in its name must not become a statusline item.
  return t.prefix .. (join_name(t.name, dropped):gsub("%%", "%%%%"))
end

--- How wide bufferline reserves the tab strip: it measures each raw label, %-codes and all.
---@param tabs workspace.TabLabel[]
---@param dropped table<workspace.NamePart, true>
---@return integer
function labels_width(tabs, dropped)
  local width = 0
  for _, t in ipairs(tabs) do
    width = width + vim.api.nvim_strwidth(tab_label(t, dropped)) + tab_frame_width
  end
  return width
end

--- The workspace tabpage already rooted at `dir`, or nil. Compared after
--- resolving symlinks, since the fish `nvim <dir>` wrapper hands over a
--- realpath while :tcd keeps whatever spelling it was given. Exact match only:
--- a subdirectory of an open project is a workspace of its own (neo-tree's
--- promote-a-subdirectory, see plugins/explorer.lua), not a duplicate.
---@param dir string
---@return integer?
function M.find(dir)
  local function real(p)
    return vim.uv.fs_realpath(p) or p
  end
  local want = real(dir)
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if M.slot(tab) and real(M.cwd(tab)) == want then
      return tab
    end
  end
end

--- Set the current (or a new) tabpage up as a workspace on `dir`.
---@param dir string project directory
---@param opts? { tab?: boolean, drop_buf?: integer, slot?: integer, agent?: boolean, background?: boolean, until_ready?: fun(ready: fun()) }
---   tab: open a new tabpage first, and scope the cwd to it with :tcd -- or,
---     if a workspace on `dir` is already open, switch to that instead of
---     opening a second one (slot is then ignored: it keeps its number).
---     Without it the directory becomes the GLOBAL cwd -- which is what startup
---     wants, so that a child process inheriting nvim's cwd lands in the project
---     rather than wherever the shell happened to be.
---   drop_buf: a buffer to delete once a real editor buffer exists (startup's
---     directory buffer, which nvim creates for `nvim <dir>`).
---   slot: the workspace number to take, if free (see M.assign_slot).
---   agent: false leaves terminal 1 a plain shell instead of M.agent_shell.
---   background: with tab, leave focus (and the mode) where it was once the tab
---     is built, for a tab an agent opened rather than you.
---   until_ready: called once the tab is built with a `ready` callback; terminal
---     1 starts only when it is called, since a Claude started in a directory
---     still being checked out would miss its CLAUDE.md and git state.
function M.open(dir, opts)
  opts = opts or {}
  dir = vim.fn.fnamemodify(dir, ":p"):gsub("/$", "")
  if vim.fn.isdirectory(dir) ~= 1 then
    vim.notify("not a directory: " .. dir, vim.log.levels.WARN)
    return
  end

  local return_to = opts.background and M.focus()
  if opts.tab then
    local existing = M.find(dir)
    if existing then
      if not return_to then
        vim.api.nvim_set_current_tabpage(existing)
      end
      return
    end
    vim.cmd("tabnew")
  end
  vim.cmd((opts.tab and "tcd " or "cd ") .. vim.fn.fnameescape(dir))
  vim.api.nvim_tabpage_set_var(0, "workspace", vim.fn.fnamemodify(dir, ":t"))
  M.assign_slot(opts.slot)
  M.set_labels() -- name the tab now; the glyphs land as its terminals report in

  -- The editor window for files to open into. Not an empty buffer: the
  -- workspace greeter (config/greeter.lua) — branch status, recent files, and
  -- pickers — which any opened file simply replaces. Not before the directory
  -- is ready: git there would describe the enclosing repo, and the greeter keeps watching it.
  if not opts.until_ready then
    require("config.greeter").open()
  end
  if opts.drop_buf then
    pcall(vim.api.nvim_buf_delete, opts.drop_buf, { force = true })
  end

  -- Capture the editor window and restore focus into it explicitly rather than
  -- with wincmd p: by the time the deferred half runs, another window may have
  -- stolen focus (Lazy's update UI popping up on startup).
  local editor = vim.api.nvim_get_current_win()
  local tab = vim.api.nvim_get_current_tabpage()
  require("util.sidebar").open() -- `show`, so focus stays here
  vim.api.nvim_set_current_win(editor)

  local function start_terminal()
    if not vim.api.nvim_tabpage_is_valid(tab) then
      return
    end
    -- Go through fishmonger so slot 1 is registered as a tab of this workspace.
    local background = require("util.background")
    require("fishmonger").show(1, {
      tab = tab,
      insert = false,
      shell = opts.agent ~= false and M.agent_shell(background.user_manager(), M.agent_name(dir))
        or nil,
    })
    if vim.api.nvim_get_current_tabpage() == tab and vim.api.nvim_win_is_valid(editor) then
      vim.api.nvim_set_current_win(editor)
      vim.cmd("stopinsert")
    end
    -- The greeter centred itself against a full-width window, and may have
    -- described a directory that was still empty: re-render it now. (snacks
    -- re-renders on WinResized, but edgy's sizing doesn't reliably produce one.)
    Snacks.dashboard.update()
  end

  vim.schedule(function()
    if opts.until_ready then
      opts.until_ready(function()
        if vim.api.nvim_win_is_valid(editor) then
          vim.api.nvim_win_call(editor, function()
            require("config.greeter").open(editor)
          end)
        end
        require("util.sidebar").refresh()
        start_terminal()
      end)
    else
      start_terminal()
    end
    if return_to then
      M.restore_focus(return_to)
    end
  end)
end

---@class workspace.Focus
---@field tab integer
---@field inserting boolean in insert or terminal mode

--- Where focus is now, for M.restore_focus.
---@return workspace.Focus
function M.focus()
  local mode = vim.api.nvim_get_mode().mode
  return {
    tab = vim.api.nvim_get_current_tabpage(),
    inserting = mode:sub(1, 1) == "i" or mode:sub(1, 1) == "t",
  }
end

--- Put focus back where M.focus found it; a tabpage closed since is left alone.
---@param focus workspace.Focus
function M.restore_focus(focus)
  if not vim.api.nvim_tabpage_is_valid(focus.tab) then
    return
  end
  vim.api.nvim_set_current_tabpage(focus.tab)
  if focus.inserting then
    vim.cmd("startinsert")
  end
end

--- What a workspace's first terminal runs: Claude, back in this directory's last
--- conversation, or a new one when there is none (--continue then exits 1). fish
--- -C runs it at the prompt, so a shell remains once Claude exits.
--- WORKSPACE_TERMINAL tells that Claude which terminal it is in, and
--- CLAUDE_AGENT_NAME what to call itself (see the session-identity mod).
---@param user_manager boolean see util/background.lua
---@param agent_name? string
---@return string|string[]
function M.agent_shell(user_manager, agent_name)
  local env = { "env", "WORKSPACE_TERMINAL=1" }
  if agent_name then
    env[#env + 1] = "CLAUDE_AGENT_NAME=" .. agent_name
  end
  return require("util.background").command(
    vim.list_extend(env, { "fish", "-C", "claude --continue; or claude" }),
    user_manager
  )
end

--- The name terminal 1's Claude in `dir` takes, if not its own: with agent
--- worktrees, a linked worktree's directory name, so every way of opening one
--- -- not only creating it -- names its agent the same. Asked of git when the
--- terminal starts, since a new worktree is only checked out by then.
---@param dir string
---@return string?
function M.agent_name(dir)
  if not options.agent_worktrees then
    return nil
  end
  local res = vim
    .system(
      { "git", "rev-parse", "--path-format=absolute", "--show-toplevel", "--git-dir", "--git-common-dir" },
      { cwd = dir, text = true }
    )
    :wait()
  local top, git_dir, common_dir = unpack(vim.split(vim.trim(res.stdout or ""), "\n"))
  if res.code == 0 and git_dir ~= common_dir then
    return vim.fs.basename(top)
  end
end

--- Fast path: pick a known project. Type a couple of letters of somewhere you
--- work often and it's the top hit (the source is frecency-ranked).
---
--- The list is snacks' `projects` source, NOT zoxide: the git roots of your recent
--- files (:oldfiles / shada), plus every repo one level inside the `dev` dirs
--- below. That's editing history rather than shell-cd history, which is the right
--- signal here -- a project you opened from the greeter or a worktree tab counts,
--- and one you only ever `cd`'d into to run a command doesn't clutter the list.
--- Same list the dashboard's Projects section shows (plugins/dashboard.lua).
---
--- We supply the list but not its default confirm (load_session), which does a
--- GLOBAL chdir into the picked directory -- dragging every existing workspace tab
--- along with it.
---
--- For a fresh clone -- nothing edited in it yet, and not under `dev` -- use
--- M.explore().
---@param opts? table passed to open(); defaults to a new tabpage. The greeter
---   (plugins/dashboard.lua) overrides it to take over the starting tab instead.
function M.pick_new(opts)
  opts = opts or { tab = true }
  Snacks.picker.projects({
    -- ~ too: repos cloned there otherwise vanish once shada stops holding a file edited in them
    dev = { "~/dev", "~" }, -- snacks' default also lists ~/projects, which doesn't exist here
    confirm = function(picker, item)
      picker:close()
      if item then
        M.open(item.file, opts)
      end
    end,
  })
end

--- Slow path: browse the filesystem for a project M.pick_new()'s list doesn't
--- know yet (a fresh clone). snacks' explorer picker, as a float over the editor
--- -- explicitly NOT neo-tree: neo-tree keys its filesystem state per TABPAGE, so
--- a browse tree and the docked sidebar are the same tree, and browsing to ~
--- re-roots the explorer
--- behind you. A picker owns its own state and leaves the sidebar alone.
---
--- Its own default layout is the `sidebar` preset, which docks it into the left
--- edge -- the one place this must not be -- so the layout is overridden here.
--- Navigation is the usual `l` / `h` / `<BS>` and typing filters live; `<CR>`
--- opens the highlighted directory as a workspace instead of expanding it, which
--- is the one thing this picker is for. `l` keeps the plain expand-or-open
--- behaviour, and so does `<Space>` -- matching neo-tree, where space toggles a
--- folder -- but only in the list window: in the input window space is a
--- literal character being typed into the filter.
---
--- Opening lives in its own action rather than in `confirm`: the explorer source
--- installs `actions.confirm` (expand the directory) in its own `config`, which
--- runs after -- and wins over -- anything passed in here, and a named action
--- beats a top-level `confirm` in key resolution. So `<CR>` is rebound to the
--- action instead, in both windows -- it's pressed in the input window while
--- filtering, and in the list once focus moves there.
---@param opts? table passed to open(); see M.pick_new.
function M.explore(opts)
  opts = opts or { tab = true }
  local open = function(picker, item)
    picker:close()
    if item then
      M.open(item.dir and item.file or vim.fs.dirname(item.file), opts)
    end
  end
  Snacks.picker.explorer({
    cwd = vim.env.HOME,
    -- Start collapsed at ~. The explorer source defaults to follow_file, which
    -- expands the tree down to the current buffer's file -- the one project
    -- this picker is never for, since it is already open.
    follow_file = false,
    -- Dotfile directories are projects too (~/.dotfiles, ~/.config/*), and the
    -- point of this picker is reaching a repo nothing has recorded yet.
    hidden = true,
    auto_close = true, -- it's a one-shot chooser here, not a panel to leave open
    layout = { preset = "dropdown", preview = false },
    actions = { workspace_open = open },
    win = {
      input = { keys = { ["<CR>"] = { "workspace_open", mode = { "n", "i" } } } },
      list = { keys = { ["<CR>"] = "workspace_open", ["<Space>"] = "confirm" } },
    },
  })
end

--- Pick an open workspace tabpage to switch to. gt/gT still cycle; this is for
--- when there are enough tabs that cycling stops being the fast way.
function M.pick()
  local items = {}
  local current = vim.api.nvim_get_current_tabpage()
  for nr, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local cwd = M.cwd(tab)
    -- The workspace number (what the label shows and <M-N> takes), falling back
    -- to the tabpage number for a tabpage that isn't a workspace.
    local n = M.slot(tab) or nr
    items[#items + 1] = {
      tab = tab,
      idx = n,
      -- Matched against as "<n> <name> <path>", so typing either the workspace
      -- number or the project name finds it.
      text = ("%d %s %s"):format(n, M.name(tab), cwd),
      file = cwd,
      dir = true,
      current = tab == current,
    }
  end
  Snacks.picker.pick({
    source = "workspaces",
    items = items,
    format = "file",
    -- A directory preview is noise for a list you already know; the path in the
    -- item line is the useful part.
    win = { preview = { minimal = true } },
    confirm = function(picker, item)
      picker:close()
      if item and vim.api.nvim_tabpage_is_valid(item.tab) then
        vim.api.nvim_set_current_tabpage(item.tab)
      end
    end,
  })
end

return M
