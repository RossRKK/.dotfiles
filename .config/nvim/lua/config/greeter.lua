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
    report = report or false
    -- Only redraw on an actual change: re-rendering an identical dashboard
    -- fights the cursor for no benefit.
    if vim.deep_equal(M.reports[root], report) then
      return
    end
    M.reports[root] = report
    -- Re-resolves every open dashboard's sections, which is how the overview
    -- appears without reopening the greeter.
    Snacks.dashboard.update()
  end)
end

--- Re-ask for the overview of every greeter currently on screen.
function M.refresh_visible()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "snacks_dashboard" then
      M.fetch(vim.fs.normalize(require("config.workspace").cwd(vim.api.nvim_win_get_tabpage(win))))
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
---@param win integer
---@return table[]
local function files(report, win)
  if not report then
    return {}
  end
  local triage = require("triage")
  -- Leave room for the header, the summary and the section title; the rest of
  -- the window is the list's.
  local limit = math.max(5, vim.api.nvim_win_get_height(win) - 12)
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

--- Show the greeter in `win` (default: the current window). The buffer is a
--- fresh scratch one -- snacks styles it bufhidden=wipe and unlisted, so opening
--- any real file over it disposes of it without a trace.
---@param win? integer
function M.open(win)
  win = win or vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  local tab = vim.api.nvim_win_get_tabpage(win)
  local workspace = require("config.workspace")
  local root = vim.fs.normalize(workspace.cwd(tab))

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
  if prev ~= buf and M.is_disposable(prev) then
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

  Snacks.dashboard.open({
    win = win,
    buf = buf,
    sections = {
      -- "<repo> - <branch>", so a worktree reads as the repo and the branch it
      -- holds (ionics/.worktrees/rkk-some-branch -> "ionics - rkk/some-branch")
      -- rather than as its checkout directory. The workspace name is the
      -- fallback for a directory git can't tell us anything about.
      function()
        local this = report()
        local name = workspace.name(tab)
        if this and this.repo then
          local branch = this.branch or this.head
          name = branch and (this.repo .. " - " .. branch) or this.repo
        end
        return {
          text = { { name, hl = "SnacksDashboardHeader" } },
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
          return files(report(), win)
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
  -- The BufEnter fallback below re-opens the greeter once the window lands on
  -- the empty replacement buffer, so nothing more to do here.
end

--- Keep the greeter as the floor of a workspace tab: whenever a window in one
--- falls back to a truly empty buffer (last buffer closed, `q` on the greeter
--- itself), show the greeter instead. Only workspace tabs -- `nvim <file>`,
--- commit messages, and the bare-nvim startup dashboard are untouched.
function M.setup()
  local group = vim.api.nvim_create_augroup("workspace_greeter", { clear = true })

  -- Keep a displayed overview honest. The branch moves outside nvim -- a commit
  -- or push in the side terminal, a lazygit session, a rebase in another window
  -- -- and none of that raises an event of its own, so the greeter re-asks on
  -- everything that plausibly follows such a move:
  --   FocusGained  came back from the terminal / another app
  --   TermClose    lazygit (or any transient terminal) exited
  --   TermLeave    left terminal mode in the side terminal
  --   BufWritePost saved a file, so the uncommitted set changed
  --   DirChanged   the tab's project changed under us
  -- Only greeters actually on screen are refreshed, the report is suppressed
  -- while one is already in flight, and an unchanged answer redraws nothing --
  -- so over-firing here costs a few small git queries, not a flicker.
  vim.api.nvim_create_autocmd(
    { "FocusGained", "TermClose", "TermLeave", "BufWritePost", "DirChanged" },
    {
      group = group,
      callback = function()
        -- Debounced: closing lazygit fires several of these at once, and the
        -- state worth reading is the one after they've all landed. stop() alone
        -- leaves the libuv handle alive, so close it too; defer_fn timers close
        -- themselves once fired, hence the is_closing guard.
        if M._pending and not M._pending:is_closing() then
          M._pending:stop()
          M._pending:close()
        end
        M._pending = vim.defer_fn(M.refresh_visible, 100)
      end,
    }
  )

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
