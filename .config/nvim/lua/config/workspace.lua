-- Workspaces: one project per nvim tabpage.
--
-- A workspace tabpage is the IDE layout (explorer left, side terminal
-- right, editor in the middle) rooted at a project directory. Opening a second
-- one gives you a second project side by side, switchable with gt/gT or the
-- picker below, without a second nvim.
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

--- What a workspace is called wherever it's on display: "<repo> - <branch>",
--- so a worktree reads as the repo and the branch it holds
--- (ionics/.worktrees/rkk-some-branch -> "ionics - rkk/some-branch") rather
--- than as its checkout directory. Drawn from the greeter's cached branch
--- report (config.greeter fetches one per workspace and watches the git dirs,
--- so it follows checkouts); before the report lands -- or for a directory git
--- can't say anything about -- it falls back to the plain workspace name.
--- Used by the tab labels below, the greeter header, and fishmonger's agent
--- view (via project_name in plugins/terminal.lua), so all three agree.
---@param tab? integer tabpage handle (default: current)
---@return string
function M.display_name(tab)
  tab = tab or vim.api.nvim_get_current_tabpage()
  -- package.loaded, not require: no reason to drag the greeter in just to name
  -- a tab, and before its setup there is no report to read anyway.
  local greeter = package.loaded["config.greeter"]
  local report = greeter and greeter.reports[vim.fs.normalize(M.cwd(tab))]
  if report and report.repo then
    local branch = report.branch or report.head
    return branch and (report.repo .. " - " .. branch) or report.repo
  end
  return M.name(tab)
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
--- setting its groups up late (VeryLazy) for free, and set_label only runs on
--- state changes.
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

--- Paint a tabpage's label on the bufferline's tab indicators: the project name,
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
---@param tab? integer tabpage handle (default: current)
function M.set_label(tab)
  tab = tab or vim.api.nvim_get_current_tabpage()
  if not vim.api.nvim_tabpage_is_valid(tab) then
    return
  end
  local fishmonger = package.loaded["fishmonger"]
  local selected = tab == vim.api.nvim_get_current_tabpage()
  local icons, coloured = {}, false
  if fishmonger then
    for _, term in ipairs(fishmonger.tabs(tab)) do
      if term.icon and term.hl then
        coloured = true
        icons[#icons + 1] = glyph_code(term.hl, selected) .. term.icon
      else
        icons[#icons + 1] = term.icon
      end
    end
  end
  -- Escaped because the label lands in the tabline as-is: a directory with a
  -- literal % in its name must not become a statusline item.
  local name = M.display_name(tab):gsub("%%", "%%%%")
  vim.api.nvim_tabpage_set_var(
    tab,
    "name",
    #icons > 0
        and (table.concat(icons) .. (coloured and restore_code(selected) or "") .. " " .. name)
      or name
  )
  -- Coalesced: the spinner tick relabels every tabpage per frame, and one
  -- redraw shows all of them -- per-call redraws re-evaluated the whole
  -- bufferline once per tab, several times a second.
  if not M._redraw_queued then
    M._redraw_queued = true
    vim.schedule(function()
      M._redraw_queued = false
      pcall(vim.cmd, "redrawtabline")
    end)
  end
end

--- Set the current (or a new) tabpage up as a workspace on `dir`.
---@param dir string project directory
---@param opts? { tab?: boolean, drop_buf?: integer }
---   tab: open a new tabpage first, and scope the cwd to it with :tcd.
---     Without it the directory becomes the GLOBAL cwd -- which is what startup
---     wants, so that a child process inheriting nvim's cwd lands in the project
---     rather than wherever the shell happened to be.
---   drop_buf: a buffer to delete once a real editor buffer exists (startup's
---     directory buffer, which nvim creates for `nvim <dir>`).
function M.open(dir, opts)
  opts = opts or {}
  dir = vim.fn.fnamemodify(dir, ":p"):gsub("/$", "")
  if vim.fn.isdirectory(dir) ~= 1 then
    vim.notify("not a directory: " .. dir, vim.log.levels.WARN)
    return
  end

  if opts.tab then
    vim.cmd("tabnew")
  end
  vim.cmd((opts.tab and "tcd " or "cd ") .. vim.fn.fnameescape(dir))
  vim.api.nvim_tabpage_set_var(0, "workspace", vim.fn.fnamemodify(dir, ":t"))
  M.set_label() -- name the tab now; the glyphs land as its terminals report in

  -- The editor window for files to open into. Not an empty buffer: the
  -- workspace greeter (config/greeter.lua) — branch status, recent files, and
  -- pickers — which any opened file simply replaces.
  require("config.greeter").open()
  if opts.drop_buf then
    pcall(vim.api.nvim_buf_delete, opts.drop_buf, { force = true })
  end

  -- Capture the editor window and restore focus into it explicitly rather than
  -- with wincmd p: by the time the deferred half runs, another window may have
  -- stolen focus (Lazy's update UI popping up on startup).
  local editor = vim.api.nvim_get_current_win()
  require("util.sidebar").open() -- `show`, so focus stays here
  vim.api.nvim_set_current_win(editor)

  vim.schedule(function()
    -- Go through fishmonger so slot 1 is registered as a tab of this workspace.
    -- insert = false because we hand focus straight back to the editor.
    require("fishmonger").show(1, { insert = false })
    if vim.api.nvim_win_is_valid(editor) then
      vim.api.nvim_set_current_win(editor)
    end
    vim.cmd("stopinsert")
    -- The greeter centred itself against a full-width window: it was drawn
    -- before the explorer and terminal took their columns. Re-render now that
    -- the editor window is its final size. (snacks re-renders on WinResized,
    -- but edgy's sizing doesn't reliably produce one for this window.)
    Snacks.dashboard.update()
  end)
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
    dev = { "~/dev" }, -- snacks' default also lists ~/projects, which doesn't exist here
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
    items[#items + 1] = {
      tab = tab,
      idx = nr,
      -- Matched against as "<n> <name> <path>", so typing either the tab number
      -- or the project name finds it.
      text = ("%d %s %s"):format(nr, M.name(tab), cwd),
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
