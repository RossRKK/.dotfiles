-- Workspaces: one project per nvim tabpage.
--
-- A workspace tabpage is the IDE layout (explorer + outline left, side terminal
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

--- A tabpage's working directory (its tab-local cwd, else the global one).
---@param tab? integer tabpage handle (default: current)
---@return string
function M.cwd(tab)
  tab = tab or vim.api.nvim_get_current_tabpage()
  local nr = vim.api.nvim_tabpage_get_number(tab)
  return vim.fn.getcwd(-1, nr)
end

--- Paint a tabpage's label on the bufferline's tab indicators: the project name,
--- prefixed with the status glyph of each of that tabpage's side terminals
--- (Claude Code's ✳/· marker — see fishmonger's title_icon). That's the point of
--- the glyphs being here rather than only in the OS title: a background project
--- whose agent is waiting on you says so from its tab, without switching to it.
---
--- bufferline renders a tabpage as `t:name` (falling back to the tab number), so
--- the label is just that variable; redrawtabline re-evaluates its %! expression.
---@param tab? integer tabpage handle (default: current)
function M.set_label(tab)
  tab = tab or vim.api.nvim_get_current_tabpage()
  if not vim.api.nvim_tabpage_is_valid(tab) then
    return
  end
  local fishmonger = package.loaded["fishmonger"]
  local icons = {}
  if fishmonger then
    for _, term in ipairs(fishmonger.tabs(tab)) do
      icons[#icons + 1] = fishmonger.title_icon(term.title)
    end
  end
  local name = M.name(tab)
  vim.api.nvim_tabpage_set_var(tab, "name", #icons > 0 and (table.concat(icons) .. " " .. name) or name)
  pcall(vim.cmd, "redrawtabline")
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

  vim.cmd.enew() -- an empty editor window for files to open into
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
  end)
end

--- Fast path: pick a project from zoxide's frecency list. Type a couple of
--- letters of somewhere you work often and it's the top hit.
---
--- snacks' zoxide source supplies the list, but not its default confirm
--- (load_session), which does a GLOBAL chdir into the picked directory --
--- dragging every existing workspace tab along with it.
---
--- Only knows directories you have actually cd'd into; for a fresh clone, or
--- anything else zoxide has never seen, use M.explore().
function M.pick_new()
  Snacks.picker.zoxide({
    confirm = function(picker, item)
      picker:close()
      if item then
        M.open(item.file, { tab = true })
      end
    end,
  })
end

--- Slow path: browse the filesystem for a project zoxide has never seen (a fresh
--- clone). snacks' explorer picker, as a float over the editor -- explicitly NOT
--- neo-tree: neo-tree keys its filesystem state per TABPAGE, so a browse tree and
--- the docked sidebar are the same tree, and browsing to ~ re-roots the explorer
--- behind you. A picker owns its own state and leaves the sidebar alone.
---
--- Its own default layout is the `sidebar` preset, which docks it into the left
--- edge -- the one place this must not be -- so the layout is overridden here.
--- Navigation is the usual `l` / `h` / `<BS>` and typing filters live; `<CR>`
--- opens the highlighted directory as a workspace instead of expanding it, which
--- is the one thing this picker is for. `l` keeps the plain expand-or-open
--- behaviour.
---
--- Opening lives in its own action rather than in `confirm`: the explorer source
--- installs `actions.confirm` (expand the directory) in its own `config`, which
--- runs after -- and wins over -- anything passed in here, and a named action
--- beats a top-level `confirm` in key resolution. So `<CR>` is rebound to the
--- action instead, in both windows -- it's pressed in the input window while
--- filtering, and in the list once focus moves there.
function M.explore()
  local open = function(picker, item)
    picker:close()
    if item then
      M.open(item.dir and item.file or vim.fs.dirname(item.file), { tab = true })
    end
  end
  Snacks.picker.explorer({
    cwd = vim.env.HOME,
    auto_close = true, -- it's a one-shot chooser here, not a panel to leave open
    layout = { preset = "dropdown", preview = false },
    actions = { workspace_open = open },
    win = {
      input = { keys = { ["<CR>"] = { "workspace_open", mode = { "n", "i" } } } },
      list = { keys = { ["<CR>"] = "workspace_open" } },
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
