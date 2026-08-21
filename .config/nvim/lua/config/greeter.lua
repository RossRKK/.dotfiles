-- Workspace greeter: what the main editor window shows when it has nothing
-- real to show.
--
-- workspace.open() used to leave a plain empty buffer there, which told you
-- nothing and did nothing. Instead the window gets a snacks dashboard scoped to
-- THIS workspace, showing where the branch stands: repo and branch, its position
-- against the remote and the review base, and the files it changes. It comes
-- back whenever the buffer list empties out again (<leader>X, or closing the
-- last buffer), so "no buffers open" is a status screen rather than a dead end.
--
-- The numbers and the file list come from triage.report (plugins/review.lua) --
-- the same merge-result diff and triage ledger review mode marks the explorer
-- with, so the greeter's list and the tree's glyphs can never disagree. It
-- reports regardless of whether review mode is on, so the overview reads the
-- same before you toggle it as after.
--
-- It is also a real, listed buffer, pinned to the front of the bufferline: one
-- per workspace, kept alive for the life of the tab rather than rebuilt each
-- time. That makes the overview somewhere you can go back to (<leader>h, a
-- click, or <S-h> off the left end) instead of only somewhere you land when the
-- last buffer closes. plugins/buffers.lua does the pinning and the filtering --
-- it keys off the b:greeter_root set below.
--
-- No pickers here: find/recent/grep have keybinds, and repeating them as a menu
-- costs the space the overview wants. The changed-file list IS the file
-- selector -- the files this branch is about, a letter away. The pickers only
-- come back as the fallback for a directory that isn't a git repo, which has no
-- overview to show.
--
-- Distinct from plugins/dashboard.lua, which is the bare-`nvim` startup greeter
-- and is about CHOOSING a project; this one assumes the project. Both are snacks
-- dashboards, so they share styling and section machinery.

local M = {}

-- Branch overview per workspace root: normalized cwd -> TriageReport, or false
-- for "asked, not a git repo" (nil means the answer hasn't arrived yet, which
-- renders as a bare header rather than as an empty repo).
--
-- Cached because triage.report is async: the dashboard has to render before the
-- git work finishes, so it draws from here and is told to redraw when a fresh
-- report lands. Keyed by root so switching tabs shows that project's overview
-- immediately, without a flash of the previous one.
M.reports = {}

-- The live greeter buffer per workspace root: normalized cwd -> buffer.
--
-- One per workspace and reused, because the greeter is now a bufferline tab: a
-- fresh buffer on every open() would give the bar a new "first tab" each time
-- the buffer list emptied, and leave the old ones behind on it. Entries are
-- dropped when the buffer dies (its tab closed, see setup()).
M.buffers = {}

--- Is this one of the persistent greeter buffers? Tagged with the root rather
--- than checked against M.buffers so the bufferline's filter (plugins/buffers.lua)
--- can ask the same question of a buffer without reaching into this module.
---@param buf integer
---@return boolean
function M.is_greeter(buf)
  return vim.api.nvim_buf_is_valid(buf) and vim.b[buf].greeter_root ~= nil
end

--- Is this buffer a spent one -- nothing in it, nothing to save, nobody's
--- scratch -- that the greeter may take the window from and delete? A previous
--- greeter counts too. Deliberately-blank buffers (M.new_file) are tagged out.
---
--- Requiring buflisted is what keeps a panel's buffer safe: a plugin's scratch
--- buffer is unlisted, and fishmonger's terminal buffer is empty, unnamed and
--- still buftype "" in the moment between being shown and having its shell
--- attached -- claiming that one drew a second greeter over the side terminal
--- and destroyed the buffer the shell was about to attach to.
---@param buf integer
---@return boolean
function M.is_disposable(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.b[buf].greeter_ignore then
    return false
  end
  if vim.bo[buf].filetype == "snacks_dashboard" then
    return true
  end
  return vim.bo[buf].buflisted
    and vim.api.nvim_buf_get_name(buf) == ""
    and vim.bo[buf].buftype == ""
    and vim.bo[buf].filetype == ""
    and not vim.bo[buf].modified
    and vim.api.nvim_buf_line_count(buf) == 1
    and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
end

--- Start an empty unnamed buffer to type into. A deliberately blank buffer is
--- indistinguishable from the spent one the fallback below exists to replace, so
--- it's tagged: without the tag, "New file" hands you a blank buffer and the
--- fallback immediately takes it back, which looks like the key doing nothing.
function M.new_file()
  require("config.windows").goto_main_window()
  vim.cmd.enew()
  vim.b[vim.api.nvim_get_current_buf()].greeter_ignore = true
  vim.cmd.startinsert()
end

-- Live dashboard instances, buffer -> the object Snacks.dashboard.open()
-- returned. Kept because Snacks.dashboard.update() cannot be trusted to reach
-- more than the newest dashboard: every instance registers its listeners in an
-- augroup CREATED BY NAME with clear = true ("snacks_dashboard"), so opening a
-- greeter wipes every older greeter's Update autocmd and they go permanently
-- stale. Calling each instance's :update() directly bypasses that event
-- plumbing. Pruned lazily: snacks styles the buffers bufhidden=wipe, so a
-- dead entry is just an invalid buffer.
local instances = {}

--- Repaint every open greeter, newest and stale-augroup ones alike.
function M.update_dashboards()
  for buf, dash in pairs(instances) do
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(dash.update, dash)
    else
      instances[buf] = nil
    end
  end
end

-- Roots with a report in flight, so a burst of events queues nothing behind the
-- first one rather than stacking git processes.
local fetching = {}

--- Kick off a branch overview for `root` and redraw the greeters if it says
--- something new. Safe to call as often as you like -- the expensive step (the
--- merge-result diff) is memoised inside triage on the base/HEAD shas, so a
--- repeat call on an unchanged branch spawns only the cheap git queries.
---@param root string workspace cwd
function M.fetch(root)
  local ok, triage = pcall(require, "triage")
  if not ok or fetching[root] then
    return
  end
  fetching[root] = true
  triage.report({ root = root }, function(report)
    fetching[root] = nil
    if report then
      M.watch(root, report)
    end
    report = report or false
    -- Only redraw on an actual change: re-rendering an identical dashboard
    -- fights the cursor for no benefit.
    if vim.deep_equal(M.reports[root], report) then
      return
    end
    M.reports[root] = report
    -- Re-resolves every open dashboard's sections, which is how the overview
    -- appears without reopening the greeter.
    M.update_dashboards()
    -- The tab labels carry the same "<repo> - <branch>" name
    -- (workspace.display_name reads this cache), so a fresh report -- the
    -- first one, or a checkout moving the branch -- has to repaint them too.
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      require("config.workspace").set_label(tab)
    end
  end)
end

--- Refresh the visible greeters shortly. Debounced, because the triggers come
--- in bursts: one `git commit` writes the index, HEAD's reflog and a ref, and
--- the state worth reading is the one after all of them have landed. stop()
--- alone leaves the libuv handle alive, so close it too; defer_fn timers close
--- themselves once fired, hence the is_closing guard.
function M.queue_refresh()
  if M._pending and not M._pending:is_closing() then
    M._pending:stop()
    M._pending:close()
  end
  M._pending = vim.defer_fn(M.refresh_visible, 100)
end

--- Re-ask for the overview of every greeter currently on screen.
function M.refresh_visible()
  for _, root in ipairs(M.visible_roots()) do
    M.fetch(root)
  end
end

--- Every distinct workspace root currently showing a greeter.
---@return string[]
function M.visible_roots()
  local roots, seen = {}, {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "snacks_dashboard" then
      local root =
        vim.fs.normalize(require("config.workspace").cwd(vim.api.nvim_win_get_tabpage(win)))
      if not seen[root] then
        seen[root], roots[#roots + 1] = true, root
      end
    end
  end
  return roots
end

-- Filesystem watchers on the git directories behind each greeter: normalized
-- root -> list of uv fs_event handles.
local watchers = {}

--- Watch a repo's git directories, so the overview follows the branch instead of
--- describing where it was when the greeter opened. Nothing that moves a branch
--- raises an autocmd -- a commit or rebase in the side terminal, a lazygit
--- session, a fetch, another nvim, a plain shell -- but all of it writes here.
---
--- Two directories, non-recursively: the worktree's own git dir (HEAD, index,
--- reflog: commit, stage, checkout, rebase) and the shared common dir
--- (packed-refs, FETCH_HEAD: a fetch bringing new upstream commits). Loose ref
--- files under refs/ are deliberately not watched -- libuv only supports
--- recursive watches on macOS/Windows, so a branch with a `/` in its name would
--- need a watcher per directory level, and everything that writes a ref also
--- touches one of these two.
---@param root string normalized workspace root
---@param report table TriageReport carrying the directories
function M.watch(root, report)
  if watchers[root] or not report.git_dir then
    return
  end
  local uv = vim.uv or vim.loop
  local handles = {}
  local dirs = { report.git_dir }
  if report.common_dir and report.common_dir ~= report.git_dir then
    dirs[#dirs + 1] = report.common_dir
  end
  for _, dir in ipairs(dirs) do
    local handle = uv.new_fs_event()
    -- A failed watch (the directory went away mid-rebase, or the inotify limit
    -- is exhausted) is not worth reporting: the events above still refresh the
    -- greeter, this just makes it prompter.
    if
      handle
      and handle:start(
          dir,
          {},
          vim.schedule_wrap(function()
            M.queue_refresh()
          end)
        )
        == 0
    then
      handles[#handles + 1] = handle
    elseif handle then
      handle:close()
    end
  end
  watchers[root] = handles
end

--- Drop the watchers for roots no longer showing a greeter. Called when a
--- greeter buffer goes away: the overview only needs watching while it's on
--- screen, and a long session would otherwise hold an inotify watch per project
--- ever visited.
function M.unwatch_hidden()
  local visible = {}
  for _, root in ipairs(M.visible_roots()) do
    visible[root] = true
  end
  for root, handles in pairs(watchers) do
    if not visible[root] then
      for _, handle in ipairs(handles) do
        handle:stop()
        handle:close()
      end
      watchers[root] = nil
    end
  end
end

--- Open a file from the overview in the main editor window (the greeter's own
--- window is the main one, but the list is also reachable from a split).
---@param path string
local function edit(path)
  require("config.windows").goto_main_window()
  vim.cmd.edit(vim.fn.fnameescape(path))
end

--- A dim text line, indented to sit under the header.
---@param chunks table[] snacks text chunks
---@return table item
local function line(chunks)
  return { text = chunks, align = "center" }
end

--- The two-line summary under the header: where the branch sits against its
--- remote, and against the base it's reviewed into. Nil when there's nothing
--- meaningful to say (no report yet, or not a repo).
---@param report table? TriageReport
---@return table[]?
local function overview(report)
  if not report then
    return nil
  end
  local dim = "SnacksDashboardDesc"
  local items = {}

  -- Remote position. An unpushed branch says so rather than showing 0/0, which
  -- would read as "in sync with a remote" -- the opposite of the truth.
  if report.upstream then
    items[#items + 1] = line({
      { "\xe2\x87\xa1" .. (report.ahead or 0) .. " ", hl = report.ahead ~= 0 and "Added" or dim },
      {
        "\xe2\x87\xa3" .. (report.behind or 0) .. "  ",
        hl = report.behind ~= 0 and "Removed" or dim,
      },
      { report.upstream, hl = dim },
    })
  else
    items[#items + 1] = line({ { "no upstream", hl = dim } })
  end

  -- Base position: the branch under review and how far ahead of it we are.
  local base = {}
  if report.base then
    -- Git-merge glyph (U+F419), the same mark triage's statusline uses for the
    -- review base.
    base[#base + 1] = { "\xef\x90\x99 " .. report.base, hl = dim }
    if (report.base_ahead or 0) > 0 then
      local n = report.base_ahead
      base[#base + 1] = { ("  %d commit%s"):format(n, n == 1 and "" or "s"), hl = dim }
    end
  end
  if report.dirty > 0 then
    base[#base + 1] = { ("  %d uncommitted"):format(report.dirty), hl = "SnacksDashboardSpecial" }
  end
  if #base > 0 then
    items[#items + 1] = line(base)
  end
  return items
end

--- The changed-file list: every file the branch is responsible for, marked with
--- its triage glyph, each a keypress from opening. Long branches are cut to what
--- the window can show, with the remainder counted -- the list is a way into the
--- files, not a report to scroll.
---@param report table? TriageReport
---@param buf integer the greeter's buffer
---@return table[]
local function files(report, buf)
  if not report then
    return {}
  end
  local triage = require("triage")
  -- Sized against whichever window is showing the greeter NOW, not the one it
  -- was opened in: the buffer outlives any single window (it's a bufferline tab
  -- you come back to), so a captured window handle goes stale -- and asking a
  -- stale one for its height is an error, which would blank the section.
  local height = 30
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == buf then
      height = vim.api.nvim_win_get_height(w)
      break
    end
  end
  -- Leave room for the header, the summary and the section title; the rest of
  -- the window is the list's.
  local limit = math.max(5, height - 12)
  local items = {}
  for i, file in ipairs(report.files) do
    if i > limit then
      local rest = #report.files - limit
      items[#items + 1] = {
        text = { { ("\xe2\x80\xa6 %d more"):format(rest), hl = "SnacksDashboardDesc" } },
        indent = 4,
      }
      break
    end
    local icon = triage.icons[file.status]
    items[#items + 1] = {
      -- A table icon is taken verbatim by snacks' formatter, which is what lets
      -- the glyph keep its own status colour instead of the dashboard's.
      icon = { icon and icon.text or "\xe2\x80\xa2", hl = icon and icon.hl, width = 1 },
      -- The repo-relative path, not the absolute one: snacks shortens a long
      -- path to initials to make it fit, and every file here shares the same
      -- root, so the root is the part worth dropping.
      file = file.rel,
      autokey = true,
      action = function()
        edit(file.path)
      end,
    }
  end
  if #items == 0 then
    items[#items + 1] = {
      text = { { "nothing changed on this branch", hl = "SnacksDashboardDesc" } },
      indent = 4,
    }
  end
  return items
end

--- The agents section: every agent running in any workspace, not just this one,
--- each a letter away from being jumped to (switch tabpage + surface its
--- terminal). The rows and the jumping are fishmonger's (fishmonger.view), so
--- the same list is one keystroke away from anywhere as a popup (<C-b>a) and
--- there is one definition of what an agent row says.
---
--- Cross-workspace on purpose, and above the branch overview: the branch is
--- still there when you get to it, while an agent stuck on a permission prompt
--- in a project you aren't looking at is costing you time right now. This is the
--- screen you land on between tasks, which makes it the right place to be told.
---@return table[]?
local function agents()
  local ok, view = pcall(require, "fishmonger.view")
  if not ok then
    return nil
  end
  local rows = view.items()
  if #rows == 0 then
    return nil
  end
  local section = { icon = " ", title = "Agents", indent = 2, padding = 1 }
  -- Column-align the titles: pad every project name to the widest one, so what
  -- each agent is doing lines up down the list instead of starting wherever
  -- that row's project name happens to end.
  local project_width = 0
  for _, row in ipairs(rows) do
    project_width = math.max(project_width, vim.fn.strdisplaywidth(row.project or ""))
  end
  for _, row in ipairs(rows) do
    section[#section + 1] = {
      -- A table icon is passed through verbatim by snacks' formatter, which is
      -- what keeps the glyph's own state colour (see the changed-files list).
      icon = { row.icon, hl = row.hl, width = 1 },
      -- A session fishmonger can't reach (an agent in a bare terminal) gets no
      -- key: it still belongs in the list -- it is still an agent waiting on you
      -- -- but there is nothing to jump to.
      key = row.action and row.key or nil,
      -- Where it is, then what it's doing (the terminal's own title, when it
      -- says more than the project name). No state WORD: the icon already says
      -- it, and repeating it in text pushed the title out of the eye line.
      -- Padded by display width, not %-Ns: project names can hold multibyte
      -- characters, and string.format counts bytes.
      desc = (row.project or "") .. (" "):rep(
        project_width - vim.fn.strdisplaywidth(row.project or "")
      ) .. (row.title and ("  " .. row.title) or ""),
      action = row.action,
    }
  end
  return section
end

--- Show this workspace's greeter in `win` (default: the current window).
---
--- The buffer is listed and kept for the life of the workspace, so it holds a
--- place on the bufferline rather than being conjured and thrown away: a second
--- call just puts the existing one back in the window.
---@param win? integer
function M.open(win)
  win = win or vim.api.nvim_get_current_win()
  local tab = vim.api.nvim_win_get_tabpage(win)
  local workspace = require("config.workspace")
  local root = vim.fs.normalize(workspace.cwd(tab))

  -- Already built for this workspace: show it and re-ask for the overview. Not
  -- rebuilt, because the buffer IS the bufferline tab -- a new one each time
  -- would renumber the bar's first entry and strand the old buffers on it.
  local existing = M.buffers[root]
  if existing and vim.api.nvim_buf_is_valid(existing) then
    if vim.api.nvim_win_get_buf(win) ~= existing then
      local outgoing = vim.api.nvim_win_get_buf(win)
      vim.api.nvim_win_set_buf(win, existing)
      -- Same spent-buffer cleanup as below, minus the greeters: another
      -- workspace's greeter looks disposable by filetype but must survive.
      if not M.is_greeter(outgoing) and M.is_disposable(outgoing) then
        pcall(vim.api.nvim_buf_delete, outgoing, { force = true })
      end
    end
    M.fetch(root)
    M.update_dashboards()
    return
  end

  -- Listed, so it appears on the bufferline; scratch, so it is never a file on
  -- disk. bufhidden is forced back to "hide" after open() below -- snacks'
  -- styling sets wipe, which would destroy the buffer (and its place on the
  -- bar) the moment you switched to a file.
  local buf = vim.api.nvim_create_buf(true, true)
  -- Tagged before open() so the bufferline's filter and sort see it on the very
  -- first redraw, rather than showing it as a stray "[No Name]" for a frame.
  vim.b[buf].greeter_root = root
  M.buffers[root] = buf

  -- Retire an outgoing dashboard BEFORE opening ours, never during. Every snacks
  -- dashboard shares one augroup NAME, so they share its id, and a dashboard
  -- buffer's BufWipeout deletes that augroup by id. Snacks' own open() sets the
  -- window's buffer as its first step, so letting it wipe the previous dashboard
  -- there deletes the augroup the half-built new one is still registering
  -- against -- "invalid group: N", mid-init, leaving nvim unusable. Doing the
  -- swap here means the wipe lands while no dashboard is initialising, and
  -- open() then creates the augroup fresh.
  --
  -- The spent buffer the greeter displaces goes the same way, for a different
  -- reason: Snacks.bufdelete leaves the window on a fresh empty LISTED buffer,
  -- which lingers in the buffer list as "[No Name]" on the bufferline once the
  -- greeter has taken the window over.
  local prev = vim.api.nvim_win_get_buf(win)
  if prev ~= buf and not M.is_greeter(prev) and M.is_disposable(prev) then
    vim.api.nvim_win_set_buf(win, buf)
    pcall(vim.api.nvim_buf_delete, prev, { force = true })
  end

  -- Always re-ask: the branch may have moved (a commit, a push, a rebase in the
  -- side terminal) since this workspace last showed its greeter.
  M.fetch(root)

  --- The cached report, or nil while it's still in flight / not a repo.
  local function report()
    local cached = M.reports[root]
    return cached ~= false and cached or nil
  end

  instances[buf] = Snacks.dashboard.open({
    win = win,
    buf = buf,
    sections = {
      -- Agents first, ABOVE the header: everything below it is about this
      -- project, and this list deliberately isn't -- it's every workspace's
      -- agents. Sitting under a "<repo> - <branch>" heading would read as a
      -- claim that these belong to this repo.
      agents,
      -- "<repo> - <branch>", the workspace's display name everywhere (tab
      -- labels, agent view): workspace.display_name reads the same report
      -- cache this greeter fills, with the plain workspace name as the
      -- fallback for a directory git can't tell us anything about.
      function()
        return {
          text = { { workspace.display_name(tab), hl = "SnacksDashboardHeader" } },
          align = "center",
          padding = 1,
        }
      end,
      function()
        local items = overview(report())
        return items and vim.list_extend(items, { { padding = 1 } }) or nil
      end,
      {
        icon = " ",
        title = "Changed Files",
        indent = 2,
        function()
          return files(report(), buf)
        end,
      },
      -- Not a git repo: there's no overview to show, so fall back to the
      -- pickers -- the only case where the greeter still needs a menu.
      function()
        if M.reports[root] ~= false then
          return nil
        end
        return {
          padding = 1,
          {
            icon = " ",
            key = "f",
            desc = "Find file",
            action = function()
              Snacks.picker.files()
            end,
          },
          {
            icon = " ",
            key = "g",
            desc = "Live grep",
            action = function()
              Snacks.picker.grep()
            end,
          },
          { icon = " ", key = "n", desc = "New file", action = M.new_file },
        }
      end,
    },
  })

  -- Undo the two pieces of snacks' styling that assume a throwaway dashboard.
  -- Set after open(), not before: styling happens inside it, so anything set
  -- earlier is overwritten. bufhidden=wipe would destroy the buffer -- and its
  -- place on the bar -- the instant you opened a file over it, which is exactly
  -- the trip back the bufferline tab exists to provide; unlisted would keep it
  -- off the bar altogether.
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].buflisted = true
end

--- Put the cursor on this workspace's greeter, building it if the workspace
--- hasn't got one yet. The <leader>h target: the bufferline tab is clickable and
--- <S-h> reaches it by cycling, but neither is a straight "take me home".
function M.focus()
  require("config.windows").goto_main_window()
  M.open()
end

--- Close every buffer belonging to this workspace tab (the same set bufferline
--- shows: file buffers under the tab's cwd, plus unnamed ones), landing back on
--- the greeter. Modified buffers get snacks' save/discard prompt rather than
--- being lost.
function M.close_all()
  require("config.windows").goto_main_window()
  local cwd = vim.fs.normalize(require("config.workspace").cwd())
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted and vim.bo[buf].buftype == "" then
      local file = vim.api.nvim_buf_get_name(buf)
      if file == "" or vim.startswith(vim.fs.normalize(file), cwd .. "/") then
        Snacks.bufdelete(buf)
      end
    end
  end
  -- Land on the greeter explicitly rather than leaving it to the BufEnter
  -- fallback. Now that the greeter is listed, bufdelete may well switch the
  -- window straight onto it -- in which case no empty buffer ever appears and
  -- the fallback never fires. open() is idempotent (it reuses this workspace's
  -- buffer), so doing both is harmless and the outcome stops depending on which
  -- of the two got there first.
  M.open()
end

--- Keep the greeter as the floor of a workspace tab: whenever a window in one
--- falls back to a truly empty buffer (last buffer closed, `q` on the greeter
--- itself), show the greeter instead. Only workspace tabs -- `nvim <file>`,
--- commit messages, and the bare-nvim startup dashboard are untouched.
function M.setup()
  local group = vim.api.nvim_create_augroup("workspace_greeter", { clear = true })

  -- The git-directory watchers (M.watch) are what actually keep the overview
  -- current -- they catch a commit, rebase or fetch whoever made it. These
  -- events are the backstop for the rest: coming back from another app, and the
  -- working-tree edits that change the uncommitted count without touching .git.
  vim.api.nvim_create_autocmd({ "FocusGained", "BufWritePost", "DirChanged" }, {
    group = group,
    callback = M.queue_refresh,
  })

  -- An agent changing state is the one thing on this screen that moves without
  -- anyone touching nvim, so the list has to repaint on its own -- a stale
  -- "working" where the agent is actually blocked is worse than not showing it.
  -- update_dashboards() re-resolves every open dashboard's sections, so
  -- background workspaces' greeters are current the moment you switch to them
  -- too.
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "FishmongerAgentsChanged",
    callback = M.update_dashboards,
  })

  -- The working-state spinner: repaint on each frame so the Agents list
  -- animates like the tab strips do -- but not while the cursor is IN a
  -- dashboard, because snacks' update() re-snaps the cursor onto the nearest
  -- item and a 150ms tick would wrestle you for it. The spinner just freezes
  -- while you navigate the greeter and resumes when you leave.
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "FishmongerAgentsTick",
    callback = function()
      if vim.bo.filetype ~= "snacks_dashboard" then
        M.update_dashboards()
      end
    end,
  })

  -- A closed workspace tab leaves its greeter behind in the (global) buffer
  -- list. The bufferline filters it off every other project's bar, so it is
  -- invisible rather than wrong -- but a long session would accumulate one per
  -- project ever opened, and <leader>h would reuse a buffer belonging to a tab
  -- that no longer exists. Reap the ones whose root no tab is rooted at.
  vim.api.nvim_create_autocmd("TabClosed", {
    group = group,
    callback = function()
      local live = {}
      for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
        live[vim.fs.normalize(require("config.workspace").cwd(tab))] = true
      end
      for root, buf in pairs(M.buffers) do
        if not live[root] then
          M.buffers[root] = nil
          if vim.api.nvim_buf_is_valid(buf) then
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
          end
        end
      end
    end,
  })

  -- Stop watching a project once its greeter is gone.
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(ev)
      if vim.bo[ev.buf].filetype == "snacks_dashboard" then
        -- Scheduled: at BufWipeout time the buffer is still in its window, so
        -- it would still count as visible.
        vim.schedule(M.unwatch_hidden)
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(ev)
      local win = vim.api.nvim_get_current_win()
      local tab_is_workspace = pcall(vim.api.nvim_tabpage_get_var, 0, "workspace")
      if
        not tab_is_workspace
        or vim.bo[ev.buf].filetype == "snacks_dashboard" -- already the greeter
        or not M.is_disposable(ev.buf)
        -- Only ever the main editor window: a panel window that happens to hold
        -- a disposable-looking buffer is not the greeter's to claim.
        or win ~= require("config.windows").main_window()
        or vim.api.nvim_win_get_config(win).relative ~= ""
      then
        return
      end
      -- Deferred: swapping the window's buffer from inside BufEnter confuses
      -- whatever command put us here (bufdelete's window juggling in particular).
      --
      -- Re-tested on the way out, not just re-identified: BufEnter fires from
      -- INSIDE the command that made the buffer, so anything that command does
      -- afterwards to claim it -- M.new_file's tag, a plugin setting a filetype
      -- or attaching a job -- has only landed by now. Trusting the entry check
      -- alone made "New file" hand back the greeter instead of a blank buffer.
      vim.schedule(function()
        if
          vim.api.nvim_win_is_valid(win)
          and vim.api.nvim_win_get_buf(win) == ev.buf
          and M.is_disposable(ev.buf)
        then
          M.open(win)
        end
      end)
    end,
  })
end

return M
