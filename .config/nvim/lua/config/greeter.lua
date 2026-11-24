-- Workspace greeter: what the main editor window shows when it has nothing
-- real to show.
--
-- workspace.open() used to leave a plain empty buffer there, which told you
-- nothing and did nothing. Instead the window shows the review queue's counts,
-- held to their height, with the todo list (config/todo.lua) under it. Above
-- it, for a branch with a PR, sit the PR stack (its rows pick a PR) and diff
-- size, then the PR itself, a gh:// buffer that snacks.nvim renders and that
-- takes the room; without a PR the todo list takes it. It comes back whenever
-- the buffer list empties out again (<leader>X, or closing the last buffer), so
-- "no buffers open" is a status screen rather than a dead end. The windows
-- around it are companions (config/windows.lua): a file opened over the
-- greeter puts them away.
--
-- The queue's buffer is a real, listed one, pinned to the front of the
-- bufferline: one per workspace, kept alive for the life of the tab rather
-- than rebuilt each time. That makes the overview somewhere you can go back to
-- (<leader>h, a click, or <S-h> off the left end) instead of only somewhere
-- you land when the last buffer closes. plugins/buffers.lua does the pinning
-- and the filtering -- it keys off the b:greeter_root set below.
--
-- The branch report (triage.report, plugins/review.lua) behind the size and the
-- PR also names the workspace's tab and the OS title, and its PR is the base
-- triage reviews against.
--
-- Distinct from plugins/dashboard.lua, which is the bare-`nvim` startup greeter
-- and is about CHOOSING a project; this one assumes the project.

local M = {}

local reports = require("util.branch_reports")

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
--- scratch -- that the greeter may take the window from and delete?
--- The start screen, a snacks dashboard, counts too.
---
--- Requiring buflisted is what keeps a panel's buffer safe: a plugin's scratch
--- buffer is unlisted, and fishmonger's terminal buffer is empty, unnamed and
--- still buftype "" in the moment between being shown and having its shell
--- attached -- claiming that one drew a second greeter over the side terminal
--- and destroyed the buffer the shell was about to attach to.
---@param buf integer
---@return boolean
function M.is_disposable(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
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

-- The greeter's text highlights.
local DIM, KEY, TITLE = "Comment", "Special", "Title"

-- Window options of the greeter's own windows, local to its buffers so a file shown there gets its own.
local PANE_WO = {
  number = false,
  relativenumber = false,
  signcolumn = "no",
  foldcolumn = "0",
  statuscolumn = "",
  cursorline = false,
  list = false,
  wrap = false,
  spell = false,
}

local new_buffer, lay_out, size_column, refresh_pr, part_window, place, pr_buffer, pr_uri, named
local stack_buffer, reviewers_buffer, part_buffer, pick_prs

--- Show this workspace's greeter in `win` (default: the current window).
---
--- The buffer is listed and kept for the life of the workspace, so it holds a
--- place on the bufferline rather than being conjured and thrown away: a second
--- call just puts the existing one back in the window.
---@param win? integer
function M.open(win)
  win = win or vim.api.nvim_get_current_win()
  local root = vim.fs.normalize(require("config.workspace").cwd(vim.api.nvim_win_get_tabpage(win)))
  local buf = M.buffers[root]
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    buf = new_buffer(root)
  end
  local outgoing = vim.api.nvim_win_get_buf(win)
  if outgoing ~= buf then
    vim.api.nvim_win_set_buf(win, buf)
    -- Snacks.bufdelete leaves an empty listed buffer, which would linger on the bufferline.
    if M.is_disposable(outgoing) then
      pcall(vim.api.nvim_buf_delete, outgoing, { force = true })
    end
  end
  -- Always re-ask: the branch may have moved since this workspace last showed its greeter.
  M.fetch(root)
  M.arrange(win, require("config.todo").FILE)
end

--- Lay the greeter out from `win`, which shows it, with the todo list under it.
---@param win integer
---@param todo_file string
function M.arrange(win, todo_file)
  local tab = vim.api.nvim_win_get_tabpage(win)
  local todo = require("config.todo")
  if not todo.window(tab, todo_file) then
    todo.open_below(win, todo_file)
  end
  lay_out(win, todo_file)
end

--- Redraw every greeter on screen, with whatever todo list its tab still shows.
function M.redraw()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    -- Valid still: laying one out closes windows this list was taken with.
    if vim.api.nvim_win_is_valid(win) and M.is_greeter(vim.api.nvim_win_get_buf(win)) then
      lay_out(win, require("config.todo").FILE)
    end
  end
end

--- Fill `win`'s greeter and the windows around it. For a branch with a PR,
--- top to bottom: the stack and the reviewers held to their rows, the PR taking
--- the room, the queue held to its lines, the todo list keeping a share.
--- Without a PR, the queue and the todo list taking the room.
---@param win integer
---@param todo_file string
function lay_out(win, todo_file)
  local buf = vim.api.nvim_win_get_buf(win)
  local root = vim.b[buf].greeter_root
  local tab = vim.api.nvim_win_get_tabpage(win)
  local width = vim.api.nvim_win_get_width(win)
  M.draw(buf, M.queue_rows(root), width)
  local pr = M.branch_pr(root)
  local pr_buf, fresh = nil, false
  if pr then
    pr_buf, fresh = pr_buffer(pr)
  end
  local stack_buf = pr and stack_buffer(root, width)
  local reviewers_buf = pr and reviewers_buffer(root, width)
  local todo_win = require("config.todo").window(tab, todo_file)

  local pr_win, shown = place(tab, "pr", pr_buf, win, { split = "above", win = win })
  if shown and not fresh then
    require("snacks.gh.buf").attached[pr_buf]:update()
  end
  -- Only ever with a PR, so each goes above the PR's window, the stack on top.
  local reviewers_win =
    place(tab, "reviewers", reviewers_buf, win, pr_win and { split = "above", win = pr_win })
  local stack_win = place(
    tab,
    "stack",
    stack_buf,
    win,
    pr_win and { split = "above", win = reviewers_win or pr_win }
  )

  local fixed = vim.tbl_filter(function(w)
    return w ~= false
  end, { stack_win or false, reviewers_win or false })
  for _, w in ipairs({ win, unpack(fixed) }) do
    for option, value in pairs(PANE_WO) do
      vim.wo[w][0][option] = value
    end
  end
  if pr_win then
    size_column(fixed, pr_win, win, todo_win, shown == "opened")
  end
  for _, w in ipairs(fixed) do
    vim.wo[w].winfixheight = true
  end
  if todo_win then
    vim.wo[todo_win].winfixheight = pr_win ~= nil
  end
  require("config.windows").hold_height(win, vim.api.nvim_buf_line_count(buf))
end

--- Size a PR's column, top to bottom: the windows above the PR and the queue
--- to their rows, the todo list to its height (a third of the room when the PR
--- has just opened), and the PR to the rest. Set explicitly, top down, the last
--- window taking what is left: with some windows fixed, nvim hands a resize's
--- spare rows to whichever neighbour it picks, not to the PR.
---@param above integer[] the windows above the PR, top to bottom
---@param pr_win integer
---@param queue_win integer
---@param todo_win integer?
---@param share boolean
function size_column(above, pr_win, queue_win, todo_win, share)
  local function rows(w)
    return vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(w))
  end
  local entries = {}
  for _, w in ipairs(above) do
    entries[#entries + 1] = { w, rows(w) }
  end
  local pr_entry = { pr_win }
  entries[#entries + 1] = pr_entry
  entries[#entries + 1] = { queue_win, rows(queue_win) }
  local total, fixed = 0, 0
  for _, entry in ipairs(entries) do
    total = total + vim.api.nvim_win_get_height(entry[1])
    fixed = fixed + (entry[2] or 0)
  end
  if todo_win then
    total = total + vim.api.nvim_win_get_height(todo_win)
    local todo = share and math.max(6, math.floor((total - fixed) / 3))
      or vim.api.nvim_win_get_height(todo_win)
    entries[#entries + 1] = { todo_win, todo }
    fixed = fixed + todo
  end
  pr_entry[2] = math.max(1, total - fixed)
  for _, entry in ipairs(entries) do
    vim.wo[entry[1]].winfixheight = false
  end
  for i = 1, #entries - 1 do
    vim.api.nvim_win_set_height(entries[i][1], entries[i][2])
  end
end

--- The queue window's rows: what is waiting on me, and on my own PRs, from the
--- review queue's background refresh (no fetch of its own).
---@param root string normalized workspace root
---@return greeter.Chunk[][]
function M.queue_rows(root)
  local rq = require("util.reviewqueue")
  local rows = vim.tbl_filter(function(row)
    return row ~= false
  end, { M.queue_line(rq.counts(root)) or false, M.mine_line(rq.counts(root, "mine")) or false })
  return #rows > 0 and rows or { { { "\u{f4af} nothing waiting on you", DIM } } }
end

--- The PR of the branch `root` has checked out, once the report and the PR
--- fetch both answer for the same branch (they disagree across a checkout).
---@param root string normalized workspace root
---@return table? pr `gh pr view` JSON
function M.branch_pr(root)
  local entry, report = M.prs[root], reports[root]
  return entry and report and entry.branch == report.branch and entry.pr or nil
end

--- The reviewers of the branch's PR, once fetched for that PR.
---@param root string normalized workspace root
---@return pr_reviewers.Reviewer[]?
function M.branch_reviewers(root)
  local pr, entry = M.branch_pr(root), M.reviewers[root]
  return pr and entry and entry.number == pr.number and entry.reviewers or nil
end

-- A review state's glyph, highlight and word, as GitHub's Reviewers panel shows it.
local REVIEW_STATES = {
  pending = { "\u{25cf}", "DiagnosticWarn", "pending" },
  commented = { "\u{f075}", DIM, "commented" },
  approved = { "\u{2713}", "Added", "approved" },
  changes_requested = { "\u{2717}", "Removed", "changes requested" },
}

--- The reviewers window's rows: one per reviewer, its state after the names,
--- a CODEOWNERS request shielded and a review's teams after its state.
---@param reviewers pr_reviewers.Reviewer[]
---@return greeter.Chunk[][]
function M.reviewer_rows(reviewers)
  if #reviewers == 0 then
    return { { { "no reviewers", DIM } } }
  end
  local name_w = 0
  for _, r in ipairs(reviewers) do
    name_w = math.max(name_w, vim.fn.strdisplaywidth(r.name))
  end
  return vim.tbl_map(function(r)
    local state = REVIEW_STATES[r.state]
    return {
      { state[1] .. " ", state[2] },
      { r.name .. (" "):rep(name_w - vim.fn.strdisplaywidth(r.name)) },
      -- Shield (nf-fa-shield), as GitHub marks a code owner.
      { r.code_owner and " \u{f132}" or "  ", KEY },
      { "  " .. state[3], state[2] },
      { #r.on_behalf_of > 0 and "  for " .. table.concat(r.on_behalf_of, ", ") or "", DIM },
    }
  end, reviewers)
end

--- The stack window's rows: the stack the branch's PR is in, from the review
--- queue's list of my open PRs (no fetch of its own), then the diff size.
---@param root string normalized workspace root
---@param width integer
---@return greeter.Chunk[][] rows, table<integer, reviewqueue.PR> prs the PR on each row
function M.stack_rows(root, width)
  local report = reports[root] or nil
  local rows, prs = {}, {}
  if not report then
    return rows, prs
  end
  local rq = require("util.reviewqueue")
  local key = rq.key(root)
  local mine = key and rq.cache[key] and rq.cache[key].mine
  local stack = mine and require("util.pr_stack").of(mine, report.branch)
  for i, row in ipairs(stack and M.stack_items(stack, width) or {}) do
    rows[#rows + 1] = row
    prs[#rows] = stack.rows[i] and stack.rows[i].pr
  end
  rows[#rows + 1] = M.size_line(report, M.attrs[root] or {})
  return rows, prs
end

--- Switch to the workspace tab whose worktree has `pr`'s branch, else check the
--- PR out in `root`.
---@param root string normalized workspace root
---@param pr reviewqueue.PR
function M.go_to_pr(root, pr)
  vim.system(
    { "git", "worktree", "list", "--porcelain" },
    { cwd = root, text = true },
    function(res)
      vim.schedule(function()
        local path = res.code == 0 and require("util.worktree").parse_worktrees(res.stdout)[pr.head]
        local tab = path and require("config.workspace").find(path)
        if tab then
          vim.api.nvim_set_current_tabpage(tab)
          return
        end
        vim.system(
          { "gh", "pr", "checkout", tostring(pr.number) },
          { cwd = root, text = true },
          function(out)
            if out.code ~= 0 then
              vim.schedule(function()
                vim.notify(
                  ("gh pr checkout %d: %s"):format(pr.number, vim.trim(out.stderr or "")),
                  vim.log.levels.ERROR
                )
              end)
            end
          end
        )
      end)
    end
  )
end

--- Refresh the PR shown for `root`'s branch.
---@param root string normalized workspace root
function refresh_pr(root)
  local pr = M.branch_pr(root)
  local buf = pr and named(pr_uri(pr))
  local attached = buf and require("snacks.gh.buf").attached[buf]
  if attached then
    attached:update()
  end
end

-- The windows above the queue, by the part of the greeter they show.
---@alias greeter.Part "stack"|"reviewers"|"pr"

--- `tab`'s window showing `part`, if it has one.
---@param tab integer
---@param part greeter.Part
---@return integer?
function part_window(tab, part)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if vim.w[win].greeter_part == part then
      return win
    end
  end
end

--- Show `buf` as `tab`'s `part`, opening its window at `anchor` (nvim_open_win
--- split config) as a companion of `under`; no `buf` closes the window.
---@param tab integer
---@param part greeter.Part
---@param buf integer?
---@param under integer the queue's window
---@param anchor? vim.api.keyset.win_config where a new window opens; nil with no `buf`
---@return integer? win, ("opened"|"swapped")? shown whether `buf` newly came into view
function place(tab, part, buf, under, anchor)
  local win = part_window(tab, part)
  if not buf then
    if win then
      vim.api.nvim_win_close(win, false)
    end
    return nil
  end
  if win then
    if vim.api.nvim_win_get_buf(win) == buf then
      return win
    end
    vim.api.nvim_win_set_buf(win, buf)
    return win, "swapped"
  end
  win = vim.api.nvim_open_win(buf, false, anchor)
  require("config.windows").mark_companion(win, under)
  vim.w[win].greeter_part = part
  return win, "opened"
end

--- `pr`'s gh:// buffer, rendered by snacks.nvim's gh module: snacks' refresh
--- after an action and its window, write and detach autocmds match the name.
---@param pr table `gh pr view` JSON
---@return integer buf, boolean fresh attached just now, so already rendering
function pr_buffer(pr)
  local uri = pr_uri(pr)
  local buf = named(uri)
  if not buf then
    buf = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_name(buf, uri)
  end
  local gh = require("snacks.gh.buf")
  if gh.attached[buf] then
    return buf, false
  end
  gh.attach(buf)
  return buf, true
end

--- The gh:// uri snacks.nvim names `pr`'s buffer by.
---@param pr table `gh pr view` JSON
---@return string
function pr_uri(pr)
  local repo, number = pr.url:match("^https?://[^/]+/([^/]+/[^/]+)/pull/(%d+)")
  return ("gh://%s/pr/%s"):format(repo, number)
end

--- The buffer named `name`, if there is one.
---@param name string
---@return integer?
function named(name)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == name then
      return buf
    end
  end
end

-- The stack table's width at most, as the dashboard pane was: wider, its columns drift apart.
local STACK_WIDTH = 90

-- Each part's buffer per workspace root, and the PR on each of the stack's rows.
local part_buffers = { stack = {}, reviewers = {} } ---@type table<greeter.Part, table<string, integer>>
local stack_prs = {} ---@type table<integer, table<integer, reviewqueue.PR>>

--- `root`'s stack buffer centred in `width` columns, or nil when it has no rows.
---@param root string
---@param width integer
---@return integer?
function stack_buffer(root, width)
  local rows, prs = M.stack_rows(root, math.min(STACK_WIDTH, width))
  if #rows == 0 then
    return nil
  end
  local buf, new = part_buffer("stack", root)
  if new then
    pick_prs(buf, root)
  end
  M.draw(buf, rows, width)
  stack_prs[buf] = prs
  return buf
end

--- `root`'s reviewers buffer centred in `width` columns, or nil before the
--- reviewers of the branch's PR are fetched.
---@param root string
---@param width integer
---@return integer?
function reviewers_buffer(root, width)
  local reviewers = M.branch_reviewers(root)
  if not reviewers then
    return nil
  end
  local buf = part_buffer("reviewers", root)
  M.draw(buf, M.reviewer_rows(reviewers), width)
  return buf
end

--- `root`'s buffer for `part`, made on first use.
---@param part greeter.Part
---@param root string
---@return integer buf, boolean new
function part_buffer(part, root)
  local buf = part_buffers[part][root]
  if buf and vim.api.nvim_buf_is_valid(buf) then
    return buf, false
  end
  buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "greeter_" .. part
  vim.bo[buf].modifiable = false
  part_buffers[part][root] = buf
  return buf, true
end

--- Make the rows of `root`'s stack buffer `buf` a picker of their PRs.
---@param buf integer
---@param root string
function pick_prs(buf, root)
  local function row_pr()
    return stack_prs[buf][vim.api.nvim_win_get_cursor(0)[1]]
  end
  vim.keymap.set("n", "G", function()
    local pr = row_pr()
    if pr then
      vim.ui.open(pr.url)
    end
  end, { buffer = buf, desc = "Open the PR in the browser" })
  vim.keymap.set("n", "<cr>", function()
    local pr = row_pr()
    if pr then
      M.go_to_pr(root, pr)
    end
  end, { buffer = buf, desc = "Go to the PR's workspace, else check it out here" })
end

---@alias greeter.Chunk { [1]: string, [2]: string? } text and its highlight group

local ns = vim.api.nvim_create_namespace("greeter")

--- Replace `buf`'s text with `rows`, one line of highlighted chunks each, centred
--- in `width` columns as one block so columns across rows stay aligned.
---@param buf integer
---@param rows greeter.Chunk[][]
---@param width integer
function M.draw(buf, rows, width)
  local widest = 0
  for _, chunks in ipairs(rows) do
    widest = math.max(
      widest,
      vim.fn.strdisplaywidth(table.concat(vim.tbl_map(function(c)
        return c[1]
      end, chunks)))
    )
  end
  local pad = (" "):rep(math.max(0, math.floor((width - widest) / 2)))
  local lines, marks = {}, {}
  for i, chunks in ipairs(rows) do
    local text = pad
    for _, chunk in ipairs(chunks) do
      if chunk[2] then
        marks[#marks + 1] = { i - 1, #text, #text + #chunk[1], chunk[2] }
      end
      text = text .. chunk[1]
    end
    lines[i] = text
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, mark in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(
      buf,
      ns,
      mark[1],
      mark[2],
      { end_col = mark[3], hl_group = mark[4] }
    )
  end
end

--- A new greeter buffer for `root`: listed, so it is on the bufferline, and
--- scratch, so it is never a file on disk.
---@param root string
---@return integer
function new_buffer(root)
  local buf = vim.api.nvim_create_buf(true, true)
  -- Tagged first, so the bufferline's filter and sort never see it untagged.
  vim.b[buf].greeter_root = root
  require("config.windows").mark_placeholder(buf)
  vim.bo[buf].filetype = "greeter"
  vim.bo[buf].modifiable = false
  M.buffers[root] = buf
  return buf
end

-- Roots with a report in flight, so a burst of events queues nothing behind the
-- first one rather than stacking git processes.
local fetching = {}

--- Kick off a branch overview for `root` and repaint what draws off it if it
--- says something new. Safe to call as often as you like -- the expensive step (the
--- merge-result diff) is memoised inside triage on the base/HEAD shas, so a
--- repeat call on an unchanged branch spawns only the cheap git queries.
---@param root string workspace cwd
function M.fetch(root)
  local ok, triage = pcall(require, "triage")
  if not ok or fetching[root] then
    return
  end
  fetching[root] = true
  -- The tab or its checkout can go while the report is in flight (<leader>tX).
  local function gone()
    return not M.live_roots()[root] or not vim.uv.fs_stat(root)
  end
  triage.report({ root = root }, function(report)
    if gone() then
      fetching[root] = nil
      return
    end
    if report then
      M.watch(root, report)
      if report.branch then
        M.fetch_pr(root, report.branch)
      end
    end
    M.read_attrs(root, report and report.files or {}, function(attrs)
      fetching[root] = nil
      if not gone() then
        M.cache_report(root, report or false, attrs)
      end
    end)
  end)
end

-- The review-tier attributes of each root's changed files (util/diffsize),
-- read alongside its report so the size line lands with the files it describes.
---@type table<string, table<string, diffsize.Attrs>>
M.attrs = {}

--- Store `report` as `root`'s overview and repaint everything drawing off it.
---@param root string workspace cwd
---@param report table|false
---@param attrs table<string, diffsize.Attrs>
function M.cache_report(root, report, attrs)
  -- Only repaint on an actual change: the labels redraw every tab.
  if vim.deep_equal(reports[root], report) and vim.deep_equal(M.attrs[root], attrs) then
    return
  end
  local old = reports[root]
  reports[root] = report
  M.attrs[root] = attrs
  -- A checkout or a commit moves what the PR shows too: its commits, checks and size.
  if old and report and (old.branch ~= report.branch or old.head ~= report.head) then
    refresh_pr(root)
  end
  M.redraw()
  -- The tab labels carry the same "<repo> - <branch>" name
  -- (workspace.display_name reads this cache), so a fresh report -- the
  -- first one, or a checkout moving the branch -- has to repaint them too.
  require("config.workspace").set_labels()
  -- The OS title carries the same names (see plugins/fishmonger.lua), but
  -- its repaints hang off fishmonger and tabpage events, none of which fire
  -- for a checkout. Announce the fresh report so it can repaint too.
  vim.api.nvim_exec_autocmds("User", { pattern = "GreeterReportChanged" })
end

--- The review-tier attributes of `files` (TriageReport entries), from the
--- checkout's own .gitattributes: the branch is checked out, so its attributes
--- are the ones that apply, a change it makes to them included. None (path
--- rules only) where git can't answer, such as a jj-only workspace.
---@param root string
---@param files { rel: string }[]
---@param cb fun(attrs: table<string, diffsize.Attrs>)
function M.read_attrs(root, files, cb)
  if #files == 0 then
    return cb({})
  end
  local diffsize = require("util.diffsize")
  local paths = vim.tbl_map(function(f)
    return f.rel
  end, files)
  vim.system(
    diffsize.attr_cmd(),
    { cwd = root, text = true, stdin = diffsize.attr_input(paths) },
    function(res)
      vim.schedule(function()
        cb(res.code == 0 and diffsize.parse_attrs(res.stdout or "") or {})
      end)
    end
  )
end

-- The reviewers of the branch's PR, per workspace root: { number, reviewers }.
---@type table<string, { number: integer, reviewers: pr_reviewers.Reviewer[] }>
M.reviewers = {}

-- The PR for the workspace's branch, per workspace root: { branch, at, pr }
-- with pr = the decoded `gh pr view` JSON, or false for "no PR". The TTL below
-- is what keeps a gh round trip off every git event.
M.prs = {}
local pr_fetching = {}
-- The watchers fetch the report on every git event; the PR moves on GitHub's
-- clock, not ours, so a minute-old answer is fine between toggles.
local PR_TTL_MS = 60 * 1000

--- Fetch the PR for `branch` into M.prs[root] and redraw on a change.
---@param root string workspace root
---@param branch string the branch the PR's head is
---@param force? boolean skip the TTL (review mode was just turned on)
function M.fetch_pr(root, branch, force)
  local cached = M.prs[root]
  if
    pr_fetching[root]
    or (not force and cached and cached.branch == branch and vim.uv.now() - cached.at < PR_TTL_MS)
  then
    return
  end
  pr_fetching[root] = true
  vim.system(
    { "gh", "pr", "view", branch, "--json", "number,state,baseRefName,url" },
    { cwd = root, text = true },
    function(res)
      vim.schedule(function()
        pr_fetching[root] = nil
        local pr = false
        if res.code == 0 then
          local ok, decoded =
            pcall(vim.json.decode, res.stdout or "", { luanil = { object = true, array = true } })
          pr = ok and type(decoded) == "table" and decoded or false
        end
        local was = cached and cached.branch == branch and M.pr_base(root, branch)
        local changed = not (cached and cached.branch == branch and vim.deep_equal(cached.pr, pr))
        M.prs[root] = { branch = branch, at = vim.uv.now(), pr = pr }
        if changed then
          M.redraw()
        end
        if pr then
          M.fetch_reviewers(root, pr)
        end
        -- triage reviews against the PR's base (pr_base): a review started
        -- before this answer, or a parent merging and GitHub retargeting the
        -- PR, has to move to the new base.
        local triage = require("triage")
        if M.pr_base(root, branch) ~= was and triage.is_enabled(root) then
          triage.refresh()
        end
      end)
    end
  )
end

--- Fetch `pr`'s reviewers into M.reviewers[root] and redraw on a change. Asked
--- with each PR fetch, so on its cadence and TTL; a failure keeps the last answer.
---@param root string workspace root
---@param pr table `gh pr view` JSON
function M.fetch_reviewers(root, pr)
  local owner, name = pr.url:match("^https?://[^/]+/([^/]+)/([^/]+)/pull/")
  local pr_reviewers = require("util.pr_reviewers")
  vim.system({
    "gh",
    "api",
    "graphql",
    "-f",
    "query=" .. pr_reviewers.QUERY,
    "-F",
    "owner=" .. owner,
    "-F",
    "name=" .. name,
    "-F",
    "number=" .. pr.number,
  }, { cwd = root, text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        return
      end
      local ok, reviewers = pcall(function()
        local reply =
          vim.json.decode(res.stdout or "", { luanil = { object = true, array = true } })
        return pr_reviewers.parse(reply)
      end)
      local entry = { number = pr.number, reviewers = reviewers }
      if ok and not vim.deep_equal(M.reviewers[root], entry) then
        M.reviewers[root] = entry
        M.redraw()
      end
    end)
  end)
end

--- triage's resolve_base (plugins/review.lua): the base of `branch`'s open PR,
--- so a stacked PR is reviewed against its parent rather than the default
--- branch. The greeter's own fetch answers first -- it's the one asked per
--- branch -- else the review queue's lists, which already hold a PR the queue
--- just opened before the greeter has fetched anything for the new worktree.
--- Nil (no PR, or not open) leaves triage to infer the parent from git.
---@param root string normalized workspace root
---@param branch string?
---@return string? base, string? label
function M.pr_base(root, branch)
  if not branch then
    return nil
  end
  local cached = M.prs[root]
  if cached and cached.branch == branch then
    local pr = cached.pr
    if pr and pr.state == "OPEN" and pr.baseRefName then
      return pr.baseRefName, "#" .. pr.number
    end
    return nil
  end
  local rq = require("util.reviewqueue")
  local key = rq.key(root)
  local entry = key and rq.cache[key]
  for _, list in ipairs({ entry and entry.items or {}, entry and entry.mine or {} }) do
    for _, item in ipairs(list) do
      if item.pr.head == branch and not item.pr.cross_repo and item.pr.base ~= "" then
        return item.pr.base, "#" .. item.pr.number
      end
    end
  end
  return nil
end

--- triage's on_toggle (plugins/review.lua): refetch the PR the moment review
--- mode comes on (it's about to be read), and refresh the queue when it
--- goes off.
---@param on boolean
---@param root string
function M.on_review_toggle(on, root)
  if not on then
    -- Leaving review mode usually means a review just went in: the queue's
    -- count should drop now, not at the next timer tick.
    require("util.reviewqueue").refresh(root)
    return
  end
  local report = reports[root]
  if report and report.branch then
    M.fetch_pr(root, report.branch, true)
  else
    M.fetch(root) -- the PR follows once the report says which branch this is
  end
end

-- Per-root debounce timers for the watcher-driven fetches below.
local queued_fetches = {}

--- Fetch `root`'s overview shortly. Debounced per root for the same reason as
--- queue_refresh, but not gated on a greeter being visible: the report cache
--- also names the workspace's tab and the OS title, so a checkout has to land
--- here even while a file is on screen.
---@param root string normalized workspace root
function M.queue_fetch(root)
  local timer = queued_fetches[root]
  if timer and not timer:is_closing() then
    timer:stop()
    timer:close()
  end
  queued_fetches[root] = vim.defer_fn(function()
    queued_fetches[root] = nil
    M.fetch(root)
  end, 100)
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
    if M.is_greeter(buf) then
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

--- Watch the directories the report names, so the overview follows the branch
--- instead of describing where it was when the greeter opened. Nothing that
--- moves a branch raises an autocmd -- a commit or rebase in the side terminal,
--- a lazygit session, a fetch, another nvim, a plain shell -- but all of it
--- writes here.
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
          vim.schedule_wrap(function(_, filename)
            -- Lock files are the churn of every read-only git command (each
            -- `git status` creates and deletes index.lock), including the ones
            -- the refresh itself runs -- reacting to them made the watcher feed
            -- itself, a permanent ~2 refreshes/sec/repo. The index is skipped
            -- too: it moves with every lock cycle, and everything the overview
            -- shows about it (the dirty count) comes from the working tree,
            -- whose edits BufWritePost already covers.
            if filename and (filename:match("%.lock$") or filename == "index") then
              return
            end
            M.queue_fetch(root)
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

--- Drop the watchers for roots no tabpage is rooted at anymore. Watchers live
--- as long as the workspace does, not just while its greeter is on screen: the
--- report cache they refresh also names the workspace's tab and the OS title,
--- which are visible the whole time. Bounded by the tabpage count, so a long
--- session still can't accumulate an inotify watch per project ever visited.
--- Called from the TabClosed reap in setup().
function M.unwatch_closed()
  local live = M.live_roots()
  for root, handles in pairs(watchers) do
    if not live[root] then
      for _, handle in ipairs(handles) do
        handle:stop()
        handle:close()
      end
      watchers[root] = nil
    end
  end
end

--- The workspace roots some tabpage is rooted at: a root's greeter, watchers
--- and fetches live as long as one is.
---@return table<string, true> normalized root -> true
function M.live_roots()
  local live = {}
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    live[vim.fs.normalize(require("config.workspace").cwd(tab))] = true
  end
  return live
end

--- The diff size by review tier (util/diffsize) of the files the report lists,
--- the merge-result diff against the review base. Nil when nothing changed.
---
--- Ours rather than GitHub's count: with the branch checked out, this diff is
--- the PR's plus any work not pushed yet, which GitHub's would lag behind.
---@param report table TriageReport
---@param attrs table<string, diffsize.Attrs>
---@return greeter.Chunk[]?
function M.size_line(report, attrs)
  if #report.files == 0 then
    return nil
  end
  local diffsize = require("util.diffsize")
  local changes = vim.tbl_map(function(f)
    -- A binary file has no lines to weigh.
    local lines = f.lines or { additions = 0, deletions = 0 }
    return { path = f.rel, additions = lines.additions, deletions = lines.deletions }
  end, report.files)
  return diffsize.chunks(diffsize.summarize(changes, attrs), DIM)
end

--- A greeter line of non-empty counts: "<glyph> 2 need you  ·  1 for your
--- team   Space rq". Nil when every count is zero (or there's no list yet).
---@param glyph string
---@param counts integer[]?
---@param parts { [1]: string, [2]: string }[] label and highlight per count; a
---   count with no part isn't shown
---@param key string
---@return greeter.Chunk[]?
local function counts_line(glyph, counts, parts, key)
  if not counts then
    return nil
  end
  local chunks = {}
  for i, p in ipairs(parts) do
    local n = counts[i] or 0
    if n > 0 then
      if #chunks > 0 then
        chunks[#chunks + 1] = { "  \u{00b7}  ", DIM }
      end
      chunks[#chunks + 1] = { ("%d %s"):format(n, p[1]), p[2] }
    end
  end
  if #chunks == 0 then
    return nil
  end
  table.insert(chunks, 1, { glyph .. " ", DIM })
  chunks[#chunks + 1] = { "   " .. key, KEY }
  return chunks
end

--- The "reviews waiting" line, from the review queue's per-tier counts. Nil
--- when nothing's waiting (or no list yet).
---@param counts integer[]? { needs you, back to you, your team }
---@return greeter.Chunk[]?
function M.queue_line(counts)
  -- Review glyph (nf-oct-code_review).
  return counts_line("\u{f4af}", counts, {
    { "need you", "DiagnosticError" },
    { "back to you", "DiagnosticWarn" },
    { "for your team", DIM },
  }, "Space rq")
end

--- The same for my own PRs. Only what's on me, or about to land: waiting on
--- reviewers (tier 5) isn't something to act on from here.
---@param counts integer[]? { to fix, to merge, to finish, queued, waiting }
---@return greeter.Chunk[]?
function M.mine_line(counts)
  -- Pull request glyph (nf-oct-git_pull_request).
  return counts_line("\u{f407}", counts, {
    { "to fix", "DiagnosticError" },
    { "ready to merge", "Added" },
    { "to finish", "DiagnosticWarn" },
    { "in merge queue", DIM },
  }, "Space rm")
end

-- A PR's checks as one glyph, by statusCheckRollup state.
local CHECK_GLYPHS = {
  SUCCESS = { "\u{2713}", "Added" },
  FAILURE = { "\u{2717}", "Removed" },
  ERROR = { "\u{2717}", "Removed" },
  PENDING = { "\u{25cf}", "DiagnosticWarn" },
  EXPECTED = { "\u{25cf}", "DiagnosticWarn" },
}

--- `text` cut to `width` display columns, an ellipsis marking the cut.
---@param text string
---@param width integer
---@return string
local function fit(text, width)
  if vim.fn.strdisplaywidth(text) <= width then
    return text
  end
  return vim.fn.strcharpart(text, 0, math.max(0, width - 1)) .. "\u{2026}"
end

--- The stack's rows, top of the stack first: the checked-out PR's
--- marker filled, each with its <leader>rm tier (or "draft") and a checks
--- glyph, then the trunk the bottom PR targets. A PR not stacked on the row
--- under it (a fork) names what it is on.
---@param stack pr_stack.Stack
---@param width integer columns the rows may take
---@return greeter.Chunk[][]
function M.stack_items(stack, width)
  local tiers = require("util.reviewqueue").MINE_TIERS
  local function status(row)
    if row.pr.draft then
      return "draft", DIM
    end
    local tier = tiers[row.verdict.tier] or { label = "?", hl = DIM }
    return tier.label, tier.hl
  end
  local num_w, status_w = 0, 0
  for _, row in ipairs(stack.rows) do
    num_w = math.max(num_w, #tostring(row.pr.number))
    status_w = math.max(status_w, vim.fn.strdisplaywidth((status(row))))
  end

  local rows = {}
  for i, row in ipairs(stack.rows) do
    local below = stack.rows[i + 1]
    local on = (below and below.pr.head or stack.trunk) ~= row.pr.base and ("  on " .. row.pr.base)
      or ""
    -- Everything but the title: "◉ ", "#N  ", "  ", the status and its "  ", the glyph.
    local title_w = width - (2 + 1 + num_w + 2 + 2 + status_w + 2 + 1)
    local title = fit(row.pr.title or "", title_w - vim.fn.strdisplaywidth(on))
    local pad = (" "):rep(title_w - vim.fn.strdisplaywidth(title) - vim.fn.strdisplaywidth(on))
    local label, label_hl = status(row)
    local check = CHECK_GLYPHS[row.pr.checks or ""] or { " " }
    rows[#rows + 1] = {
      { row.current and "\u{25c9} " or "\u{25cb} ", row.current and KEY or DIM },
      { ("#%-" .. num_w .. "d  "):format(row.pr.number), KEY },
      { title, row.current and TITLE or "Normal" },
      { on, DIM },
      { pad .. "  " },
      { label .. (" "):rep(status_w - vim.fn.strdisplaywidth(label)) .. "  ", label_hl },
      { check[1], check[2] },
    }
  end
  rows[#rows + 1] = { { "\u{2570} " .. stack.trunk, DIM } }
  return rows
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

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "ReviewQueueChanged",
    callback = M.redraw,
  })

  -- Centred against the window's width, so a resize re-centres.
  vim.api.nvim_create_autocmd("WinResized", {
    group = group,
    callback = M.redraw,
  })

  -- Back in a window (a bufferline click, <S-h>), the greeter lays its companions out again.
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function(ev)
      if not M.is_greeter(ev.buf) then
        return
      end
      local win = vim.api.nvim_get_current_win()
      -- Deferred, as the BufEnter fallback below: splitting inside the command showing it confuses that command.
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == ev.buf then
          M.arrange(win, require("config.todo").FILE)
        end
      end)
    end,
  })

  -- A new workspace's editor window starts on its greeter rather than an empty buffer.
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "WorkspaceReady",
    -- Nested so the start screen it replaces gets its BufDelete, on which snacks restores laststatus.
    nested = true,
    callback = function(ev)
      M.open(ev.data.win)
    end,
  })

  -- A closed workspace tab leaves its greeter behind in the (global) buffer
  -- list. The bufferline filters it off every other project's bar, so it is
  -- invisible rather than wrong -- but a long session would accumulate one per
  -- project ever opened, and <leader>h would reuse a buffer belonging to a tab
  -- that no longer exists. Reap the ones whose root no tab is rooted at, their
  -- stack buffers and the git-directory watchers with them (see unwatch_closed).
  vim.api.nvim_create_autocmd("TabClosed", {
    group = group,
    callback = function()
      local live = M.live_roots()
      for _, buffers in ipairs({ M.buffers, part_buffers.stack, part_buffers.reviewers }) do
        for root, buf in pairs(buffers) do
          if not live[root] then
            buffers[root] = nil
            if vim.api.nvim_buf_is_valid(buf) then
              pcall(vim.api.nvim_buf_delete, buf, { force = true })
            end
          end
        end
      end
      M.unwatch_closed()
    end,
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(ev)
      local win = vim.api.nvim_get_current_win()
      local tab_is_workspace = pcall(vim.api.nvim_tabpage_get_var, 0, "workspace")
      if
        not tab_is_workspace
        or vim.bo[ev.buf].filetype == "snacks_dashboard" -- the start screen, handed over on WorkspaceReady
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
      -- afterwards to claim it -- a plugin setting a filetype or attaching a
      -- job -- has only landed by now.
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
