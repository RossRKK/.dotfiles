-- Layout decisions in config/greeter.lua that would otherwise show up as a
-- crowded or crooked greeter.

local assert = require("luassert")
local greeter = require("config.greeter")
local todo = require("config.todo")
local rq = require("util.reviewqueue")

--- The text of a row of chunks.
---@param chunks greeter.Chunk[]
---@return string
local function text(chunks)
  return table.concat(vim.tbl_map(function(c)
    return c[1]
  end, chunks))
end

describe("greeter.open", function()
  local todo_file = vim.fs.normalize(vim.fn.tempname() .. "-todo.md")
  local saved_file, saved_counts, win

  before_each(function()
    vim.cmd("silent! only!")
    require("config.windows").setup()
    saved_file, saved_counts = todo.FILE, rq.counts
    todo.FILE = todo_file
    rq.counts = function(_, list)
      return list == "mine" and { 1, 0, 0, 0, 0 } or { 2, 0, 0 }
    end
    win = vim.api.nvim_get_current_win()
  end)

  after_each(function()
    todo.FILE, rq.counts = saved_file, saved_counts
    vim.api.nvim_del_augroup_by_name("main_companions")
    vim.cmd("silent! only!")
  end)

  local function todo_windows()
    return vim.tbl_filter(function(w)
      return vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w)) == todo_file
    end, vim.api.nvim_tabpage_list_wins(0))
  end

  it("holds the queue to its lines, with the todo list under it taking the rest", function()
    local area = vim.api.nvim_win_get_height(win)
    greeter.open(win)

    local buf = vim.api.nvim_win_get_buf(win)
    assert.is_true(greeter.is_greeter(buf))
    assert.equals(2, vim.api.nvim_buf_line_count(buf))
    assert.equals(2, vim.api.nvim_win_get_height(win))
    local list = assert(todo_windows()[1])
    assert.equals(
      vim.fn.win_screenpos(win)[1] + 3,
      vim.fn.win_screenpos(list)[1],
      "under the queue and its statusline"
    )
    assert.equals(area - 3, vim.api.nvim_win_get_height(list))
    assert.equals(win, vim.api.nvim_get_current_win())
  end)

  it("centres the queue's lines as one block in its window", function()
    greeter.open(win)
    local rows = { "\u{f4af} 2 need you   Space rq", "\u{f407} 1 to fix   Space rm" }
    local widest = math.max(vim.fn.strdisplaywidth(rows[1]), vim.fn.strdisplaywidth(rows[2]))
    local pad = (" "):rep(math.floor((vim.api.nvim_win_get_width(win) - widest) / 2))
    assert.same(
      { pad .. rows[1], pad .. rows[2] },
      vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
    )
  end)

  it("centres the queue again when its window is resized", function()
    greeter.setup()
    greeter.open(win)
    vim.cmd("vsplit")
    local buf = vim.api.nvim_win_get_buf(win)
    local before = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]:match("^ *")
    vim.api.nvim_win_set_width(win, 40)
    -- Fired by hand: a headless nvim has no UI to redraw for, so never fires it itself.
    vim.api.nvim_exec_autocmds("WinResized", {})
    local after = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]:match("^ *")
    vim.api.nvim_del_augroup_by_name("workspace_greeter")
    assert.is_true(#after < #before)
  end)

  it("does not stack a second todo list when reopened", function()
    greeter.open(win)
    greeter.open(win)
    assert.equals(1, #todo_windows())
  end)

  it("keeps the queue's window options to the greeter, not a file shown after it", function()
    vim.o.number = true
    greeter.open(win)
    assert.is_false(vim.wo[win].number)

    local file = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(file, vim.fn.tempname())
    vim.api.nvim_win_set_buf(win, file)
    assert.is_true(vim.wo[win].number)
    vim.o.number = false
  end)
end)

describe("greeter.queue_rows", function()
  local saved

  before_each(function()
    saved = rq.counts
  end)

  after_each(function()
    rq.counts = saved
  end)

  it("lists what is waiting on me, then on my own PRs", function()
    rq.counts = function(_, list)
      return list == "mine" and { 1, 0, 0, 0, 0 } or { 2, 0, 0 }
    end
    assert.same(
      { "\u{f4af} 2 need you   Space rq", "\u{f407} 1 to fix   Space rm" },
      vim.tbl_map(text, greeter.queue_rows("/repo"))
    )
  end)

  it("says nothing is waiting when no list has anything, or there is no list", function()
    rq.counts = function() end
    assert.same({ "\u{f4af} nothing waiting on you" }, vim.tbl_map(text, greeter.queue_rows("/x")))
  end)
end)

describe("greeter.draw", function()
  it("writes each row as a line, its chunks highlighted, and leaves it read-only", function()
    local buf = vim.api.nvim_create_buf(false, true)
    greeter.draw(buf, { { { "ab", "Comment" }, { "cd" } }, { { "e", "Special" } } }, 4)

    assert.same({ "abcd", "e" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    local marks = vim.tbl_map(function(m)
      return { m[2], m[3], m[4].end_col, m[4].hl_group }
    end, vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true }))
    assert.same({ { 0, 0, 2, "Comment" }, { 1, 0, 1, "Special" } }, marks)
    assert.is_false(vim.bo[buf].modifiable)
  end)

  it("centres the rows as one block, the widest setting every row's padding", function()
    local buf = vim.api.nvim_create_buf(false, true)
    greeter.draw(buf, { { { "ab", "Comment" }, { "cd" } }, { { "e", "Special" } } }, 11)

    assert.same({ "   abcd", "   e" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    local marks = vim.tbl_map(function(m)
      return { m[2], m[3], m[4].end_col }
    end, vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true }))
    assert.same({ { 0, 3, 5 }, { 1, 3, 4 } }, marks)
  end)

  it("does not pad rows wider than the window", function()
    local buf = vim.api.nvim_create_buf(false, true)
    greeter.draw(buf, { { { "abcdef" } } }, 4)
    assert.same({ "abcdef" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)
end)

describe("greeter.size_line", function()
  local function file(rel, lines)
    return { path = "/repo/" .. rel, rel = rel, status = "changed", lines = lines }
  end

  it("sizes the report's files by tier, a binary file weighing nothing", function()
    local report = {
      files = {
        file("src/a.rs", { additions = 12, deletions = 3 }),
        file("logo.png", nil),
        file("Cargo.lock", { additions = 900, deletions = 0 }),
      },
    }
    local bar = ("\u{2588}"):rep(16) .. ("\u{2591}"):rep(8)
    assert.equals(
      "+12 -3  " .. bar .. "  15 code \u{00b7} 900 generated",
      text(greeter.size_line(report, {}))
    )
  end)

  it("moves a file between tiers by its attributes", function()
    local report = { files = { file("gen/api.rs", { additions = 4, deletions = 0 }) } }
    assert.equals(
      "+0 -0  " .. ("\u{2591}"):rep(8) .. "  4 generated",
      text(greeter.size_line(report, { ["gen/api.rs"] = { generated = true } }))
    )
  end)

  it("is absent when nothing changed", function()
    assert.is_nil(greeter.size_line({ files = {} }, {}))
  end)
end)

describe("greeter.queue_line", function()
  it("is absent when nothing is waiting or there is no list yet", function()
    assert.is_nil(greeter.queue_line(nil))
    assert.is_nil(greeter.queue_line({ 0, 0, 0 }))
  end)

  it("lists only the non-empty tiers", function()
    assert.equals(
      "\u{f4af} 2 need you  \u{00b7}  1 for your team   Space rq",
      text(greeter.queue_line({ 2, 0, 1 }))
    )
  end)
end)

describe("greeter.mine_line", function()
  it("leaves out PRs that are only waiting on reviewers", function()
    assert.is_nil(greeter.mine_line(nil))
    assert.is_nil(greeter.mine_line({ 0, 0, 0, 0, 5 }))
  end)

  it("lists what's on me and what's about to land", function()
    assert.equals(
      "\u{f407} 1 to fix  \u{00b7}  4 to finish  \u{00b7}  2 in merge queue   Space rm",
      text(greeter.mine_line({ 1, 0, 4, 2, 3 }))
    )
  end)
end)

describe("greeter.pr_base", function()
  local rq = require("util.reviewqueue")
  local root = "/repo/wt"
  local saved_key

  before_each(function()
    greeter.prs = {}
    rq.cache = {}
    saved_key = rq.key
    rq.key = function()
      return "/repo"
    end
  end)

  after_each(function()
    greeter.prs = {}
    rq.cache = {}
    rq.key = saved_key
  end)

  local function queued(list, pr)
    rq.cache["/repo"] = rq.cache["/repo"] or { items = {}, mine = {} }
    table.insert(rq.cache["/repo"][list], { pr = pr, verdict = {} })
  end

  it("answers with the open PR's base and number", function()
    greeter.prs[root] =
      { branch = "feat/b", at = 0, pr = { number = 7, state = "OPEN", baseRefName = "feat/a" } }
    local base, label = greeter.pr_base(root, "feat/b")
    assert.equals("feat/a", base)
    assert.equals("#7", label)
  end)

  it("ignores a merged or closed PR, so triage infers instead", function()
    greeter.prs[root] =
      { branch = "feat/b", at = 0, pr = { number = 7, state = "MERGED", baseRefName = "feat/a" } }
    queued("mine", { number = 7, head = "feat/b", base = "feat/a" })
    assert.is_nil(greeter.pr_base(root, "feat/b"))
  end)

  it("trusts the greeter's 'no PR' over the queue for the same branch", function()
    greeter.prs[root] = { branch = "feat/b", at = 0, pr = false }
    queued("items", { number = 7, head = "feat/b", base = "feat/a" })
    assert.is_nil(greeter.pr_base(root, "feat/b"))
  end)

  it("falls back to the queue's lists before the greeter has fetched the branch", function()
    greeter.prs[root] =
      { branch = "other", at = 0, pr = { number = 1, state = "OPEN", baseRefName = "x" } }
    queued("items", { number = 9, head = "theirs", base = "main" })
    queued("mine", { number = 8, head = "feat/b", base = "feat/a" })
    local base, label = greeter.pr_base(root, "feat/b")
    assert.equals("feat/a", base)
    assert.equals("#8", label)
  end)

  it("skips fork PRs, whose branch name means nothing locally", function()
    queued("items", { number = 9, head = "feat/b", base = "feat/a", cross_repo = true })
    assert.is_nil(greeter.pr_base(root, "feat/b"))
  end)

  it("is nil without a branch", function()
    assert.is_nil(greeter.pr_base(root, nil))
  end)
end)

-- Regression: <leader>tX closes the tab and deletes its checkout while a report
-- is in flight; acting on it ran `gh` with the deleted checkout as its cwd.
describe("greeter.fetch", function()
  local saved, calls, dir

  before_each(function()
    saved = {
      triage = package.loaded.triage,
      fetch_pr = greeter.fetch_pr,
      watch = greeter.watch,
      cache_report = greeter.cache_report,
      read_attrs = greeter.read_attrs,
    }
    calls = {}
    package.loaded.triage = {
      report = function(_, cb)
        cb({ branch = "feat", git_dir = "/x/.git" })
      end,
    }
    for _, name in ipairs({ "fetch_pr", "watch", "cache_report" }) do
      greeter[name] = function()
        calls[#calls + 1] = name
      end
    end
    greeter.read_attrs = function(_, _, cb)
      calls[#calls + 1] = "read_attrs"
      cb({})
    end
    dir = vim.fs.normalize(vim.fn.tempname())
    vim.fn.mkdir(dir, "p")
  end)

  after_each(function()
    package.loaded.triage = saved.triage
    greeter.fetch_pr, greeter.watch, greeter.cache_report, greeter.read_attrs =
      saved.fetch_pr, saved.watch, saved.cache_report, saved.read_attrs
    vim.cmd("silent! tabonly!")
    vim.fn.delete(dir, "rf")
  end)

  --- A tab rooted at `dir`, then back to the first tab (a current tab's
  --- deleted cwd reads as "", another tab's still reads as the path).
  local function open_tab()
    vim.cmd("tabnew")
    vim.cmd.tcd(vim.fn.fnameescape(dir))
    vim.cmd("tabfirst")
  end

  for _, case in ipairs({
    {
      "acts on a report for a live tab's checkout",
      open_tab,
      { "watch", "fetch_pr", "read_attrs", "cache_report" },
    },
    { "drops a report whose tab has closed", function() end, {} },
    {
      "drops a report whose checkout was deleted under its tab",
      function()
        open_tab()
        vim.fn.delete(dir, "rf")
      end,
      {},
    },
  }) do
    it(case[1], function()
      case[2]()
      greeter.fetch(dir)
      assert.same(case[3], calls)
    end)
  end
end)

describe("greeter.reviewer_rows", function()
  --- A reviewer with the fields a row reads.
  local function reviewer(name, state, extra)
    return vim.tbl_extend(
      "force",
      { name = name, kind = "user", code_owner = false, state = state, on_behalf_of = {} },
      extra or {}
    )
  end

  it("aligns each reviewer's state after the names, code owners shielded", function()
    assert.same(
      {
        "\u{25cf} acme/physics \u{f132}  pending",
        "\u{25cf} bob" .. (" "):rep(13) .. "pending",
        "\u{2713} dave" .. (" "):rep(12) .. "approved  for acme/devs, acme/orchestrator",
        "\u{2717} eve" .. (" "):rep(13) .. "changes requested",
        "\u{f075} claude" .. (" "):rep(10) .. "commented",
      },
      vim.tbl_map(
        text,
        greeter.reviewer_rows({
          reviewer("acme/physics", "pending", { kind = "team", code_owner = true }),
          reviewer("bob", "pending"),
          reviewer("dave", "approved", { on_behalf_of = { "acme/devs", "acme/orchestrator" } }),
          reviewer("eve", "changes_requested"),
          reviewer("claude", "commented"),
        })
      )
    )
  end)

  it("says so when nobody is requested or has reviewed", function()
    assert.same({ "no reviewers" }, vim.tbl_map(text, greeter.reviewer_rows({})))
  end)
end)

describe("greeter.stack_items", function()
  local function texts(rows)
    return vim.tbl_map(text, rows)
  end

  --- A stack row: `pr` over a plain waiting PR, `extra` over the row.
  local function row(pr, extra)
    return vim.tbl_extend("force", {
      pr = vim.tbl_extend("force", { title = "PR " .. pr.number, draft = false }, pr),
      verdict = { tier = 5 },
      current = false,
    }, extra or {})
  end

  local stack = {
    rows = {
      row({ number = 30, title = "Top", head = "c", base = "b", draft = true }),
      row({ number = 20, head = "b", base = "a" }, { current = true, verdict = { tier = 1 } }),
      row({ number = 10, title = "Bottom", head = "a", base = "main", checks = "SUCCESS" }),
    },
    trunk = "main",
  }

  it("lists the stack top first, fills the checked-out PR's marker, ends at the trunk", function()
    local t = texts(greeter.stack_items(stack, 50))
    assert.matches("^\u{25cb} #30  Top +draft", t[1])
    assert.matches("^\u{25c9} #20  PR 20 +to fix", t[2])
    assert.matches("^\u{25cb} #10  Bottom +waiting +\u{2713}$", t[3])
    assert.equals("\u{2570} main", t[4])
  end)

  it("pads every row to the width, cutting a long title", function()
    local long = vim.deepcopy(stack)
    long.rows[1].pr.title = ("word "):rep(30)
    local t = texts(greeter.stack_items(long, 50))
    for i = 1, 3 do
      assert.equals(50, vim.fn.strdisplaywidth(t[i]))
    end
    assert.matches("\u{2026}", t[1])
  end)

  it("takes only the width its longest title needs when given more", function()
    for _, row in ipairs(vim.list_slice(texts(greeter.stack_items(stack, 200)), 1, 3)) do
      -- "◉ #30  " + "Bottom" + "  " + "waiting" + "  " + the glyph.
      assert.equals(2 + 1 + 2 + 2 + 6 + 2 + 7 + 2 + 1, vim.fn.strdisplaywidth(row))
    end
  end)

  it("names the base of a PR not stacked on the row below it", function()
    local fork = {
      rows = {
        row({ number = 3, head = "c", base = "a" }),
        row({ number = 2, head = "b", base = "a" }),
        row({ number = 1, head = "a", base = "main" }),
      },
      trunk = "main",
    }
    local t = texts(greeter.stack_items(fork, 50))
    assert.matches("PR 3  on a", t[1])
    assert.is_nil(t[2]:find(" on ", 1, true))
    assert.is_nil(t[3]:find(" on ", 1, true))
  end)
end)

-- The windows under the queue for a branch with a PR. The PR buffer is attached
-- by a stand-in for snacks.gh.buf: the real one renders from the GitHub API.
describe("greeter's PR windows", function()
  local reports = require("util.branch_reports")
  local todo_file = vim.fs.normalize(vim.fn.tempname() .. "-todo.md")
  local repo = vim.fs.normalize(vim.fn.tempname())
  local saved, gh, root, win

  local function git(...)
    local res = vim.system({ "git", "-C", repo, ... }):wait()
    assert(res.code == 0, res.stderr)
  end
  vim.fn.mkdir(repo, "p")
  git("init", "-q")
  git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init")
  git("worktree", "add", "-q", "-b", "a", repo .. "/wt-a")

  local function mine(number, head, base)
    return {
      pr = {
        number = number,
        title = "PR " .. number,
        head = head,
        base = base,
        url = "https://github.com/o/r/pull/" .. number,
      },
      verdict = { tier = 5 },
    }
  end

  --- The branch's PR as the greeter fetched it.
  local function pr(number)
    return { number = number, state = "OPEN", url = "https://github.com/o/r/pull/" .. number }
  end

  local function report(head)
    return {
      branch = "b",
      head = head,
      files = { { path = repo .. "/x.rs", rel = "x.rs", lines = { additions = 3, deletions = 1 } } },
    }
  end

  before_each(function()
    vim.cmd("silent! tabonly!")
    vim.cmd("silent! only!")
    vim.cmd.tcd(vim.fn.fnameescape(repo))
    require("config.windows").setup()
    root = repo
    saved = {
      file = todo.FILE,
      counts = rq.counts,
      key = rq.key,
      gh = package.loaded["snacks.gh.buf"],
      open = vim.ui.open,
    }
    todo.FILE = todo_file
    rq.counts = function() end
    rq.key = function()
      return "/repo"
    end
    rq.cache["/repo"] = { mine = { mine(1, "a", "main"), mine(2, "b", "a") } }
    gh = { attached = {} }
    function gh.attach(buf)
      local attached = { updates = 0 }
      function attached.update(self)
        self.updates = self.updates + 1
      end
      gh.attached[buf] = attached
      return attached
    end
    package.loaded["snacks.gh.buf"] = gh
    reports[root] = report("abc")
    greeter.attrs[root] = {}
    greeter.prs[root] = { branch = "b", at = 0, pr = pr(2) }
    win = vim.api.nvim_get_current_win()
  end)

  after_each(function()
    todo.FILE, rq.counts, rq.key, vim.ui.open = saved.file, saved.counts, saved.key, saved.open
    package.loaded["snacks.gh.buf"] = saved.gh
    rq.cache, reports[root], greeter.attrs[root], greeter.prs[root] = {}, nil, nil, nil
    vim.api.nvim_del_augroup_by_name("main_companions")
    vim.cmd("silent! tabonly!")
    vim.cmd("silent! only!")
  end)

  --- This tab's windows top to bottom, each as its buffer's name or filetype.
  local function column()
    local wins = vim.api.nvim_tabpage_list_wins(0)
    table.sort(wins, function(a, b)
      return vim.fn.win_screenpos(a)[1] < vim.fn.win_screenpos(b)[1]
    end)
    return vim.tbl_map(function(w)
      local buf = vim.api.nvim_win_get_buf(w)
      local name = vim.api.nvim_buf_get_name(buf)
      return name == todo_file and "todo" or name ~= "" and name or vim.bo[buf].filetype
    end, wins),
      wins
  end

  it("stacks the stack, the PR, the queue and the todo list, top to bottom", function()
    greeter.open(win)
    local names, wins = column()
    assert.same({ "greeter_stack", "gh://o/r/pr/2", "greeter", "todo" }, names)
    assert.is_not_nil(gh.attached[vim.api.nvim_win_get_buf(wins[2])])
    local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(wins[1]), 0, -1, false)
    assert.matches("^ *\u{25c9} #2  PR 2", lines[1])
    assert.matches("^ *\u{25cb} #1  PR 1", lines[2])
    assert.equals("\u{2570} main", vim.trim(lines[3]))
    assert.matches("^ *%+3 %-1", lines[4])
  end)

  it("leaves one blank row above the stack, outside its buffer", function()
    greeter.open(win)
    local _, wins = column()
    local stack = wins[1]
    vim.cmd.redraw()
    assert.equals(vim.fn.win_screenpos(stack)[1] + 1, vim.fn.screenpos(stack, 1, 1).row)
    assert.equals("", vim.trim(vim.fn.screenstring(vim.fn.win_screenpos(stack)[1], 1)))
    assert.equals(
      vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(stack)),
      vim.api.nvim_win_get_height(stack)
    )
    assert.matches(
      "^ *\u{25c9} #2",
      vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(stack), 0, 1, false)[1]
    )
    assert.equals("", vim.wo[wins[3]].winbar, "the queue's window has none")
  end)

  --- The stack window's lines, the greeter opened `columns` wide.
  local function stack_lines(columns)
    vim.o.columns = columns
    greeter.open(win)
    local _, wins = column()
    local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(wins[1]), 0, -1, false)
    vim.o.columns = 80
    return lines
  end

  it("centres the stack as one block, its columns kept aligned", function()
    local lines = stack_lines(140)
    local widest = 0
    for _, l in ipairs(lines) do
      widest = math.max(widest, vim.fn.strdisplaywidth(vim.trim(l)))
    end
    local pad = (" "):rep(math.floor((140 - widest) / 2))
    for _, l in ipairs(lines) do
      assert.equals(pad, l:match("^ *"))
    end
    assert.equals(vim.fn.strdisplaywidth(lines[1]), vim.fn.strdisplaywidth(lines[2]))
  end)

  it("keeps a margin either side of a stack too wide for its window", function()
    rq.cache["/repo"].mine[2].pr.title = ("word "):rep(30)
    local lines = stack_lines(60)
    assert.equals("  ", lines[1]:match("^ *"))
    assert.equals(60 - 2, vim.fn.strdisplaywidth(lines[1]), "the row, then a margin as wide")
  end)

  it("shows a PR stacked with nothing as a one-row stack that G opens", function()
    local opened
    vim.ui.open = function(path, _)
      opened = path
      return nil, nil
    end
    rq.cache["/repo"] = { mine = { mine(2, "b", "main") } }
    greeter.open(win)
    local names, wins = column()
    local stack_win = wins[assert(vim.iter(ipairs(names)):find(function(_, n)
      return n == "greeter_stack"
    end))]
    local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(stack_win), 0, -1, false)
    local row = assert(vim.iter(ipairs(lines)):find(function(_, l)
      return l:find("\u{25c9} #2  PR 2", 1, true) ~= nil
    end))
    assert.is_truthy(vim.iter(lines):find(function(l)
      return vim.trim(l) == "\u{2570} main"
    end))
    vim.api.nvim_win_call(stack_win, function()
      vim.api.nvim_win_set_cursor(0, { row, 0 })
      vim.cmd("normal G")
    end)
    assert.equals("https://github.com/o/r/pull/2", opened)
  end)

  it(
    "holds the stack and the queue to their rows and the todo list to a share, the PR taking the rest",
    function()
      greeter.open(win)
      local _, wins = column()
      assert.equals(4, vim.api.nvim_win_get_height(wins[1]))
      assert.equals(1, vim.api.nvim_win_get_height(wins[3]))
      assert.is_true(vim.wo[wins[3]].winfixheight)
      assert.same(
        { true, false, true },
        { vim.wo[wins[1]].winfixheight, vim.wo[wins[2]].winfixheight, vim.wo[wins[4]].winfixheight }
      )
      assert.is_true(vim.api.nvim_win_get_height(wins[2]) > vim.api.nvim_win_get_height(wins[4]))
    end
  )

  it("puts the PR's reviewers between the stack and the PR, held to their rows", function()
    greeter.reviewers[root] = {
      number = 2,
      reviewers = {
        {
          name = "acme/devs",
          kind = "team",
          code_owner = true,
          state = "pending",
          on_behalf_of = {},
        },
        { name = "bob", kind = "user", code_owner = false, state = "approved", on_behalf_of = {} },
      },
    }
    greeter.open(win)
    local names, wins = column()
    greeter.reviewers[root] = nil
    assert.same({ "greeter_stack", "greeter_reviewers", "gh://o/r/pr/2", "greeter", "todo" }, names)
    local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(wins[2]), 0, -1, false)
    assert.matches("acme/devs", lines[1])
    assert.matches("bob", lines[2])
    assert.equals(2, vim.api.nvim_win_get_height(wins[2]))
    assert.is_true(vim.wo[wins[2]].winfixheight)
  end)

  it("has no reviewers window for reviewers fetched for another PR", function()
    greeter.reviewers[root] = { number = 9, reviewers = {} }
    greeter.open(win)
    local names = column()
    greeter.reviewers[root] = nil
    assert.same({ "greeter_stack", "gh://o/r/pr/2", "greeter", "todo" }, names)
  end)

  it("has only the todo list under the queue for a branch without a PR", function()
    greeter.prs[root].pr = false
    greeter.open(win)
    local names, wins = column()
    assert.same({ "greeter", "todo" }, names)
    assert.is_false(vim.wo[wins[2]].winfixheight)
  end)

  it("puts the stack and the PR away when the branch's PR goes", function()
    greeter.open(win)
    greeter.prs[root].pr = false
    greeter.redraw()
    local names, wins = column()
    assert.same({ "greeter", "todo" }, names)
    assert.is_false(vim.wo[wins[2]].winfixheight)
  end)

  it("shows the branch's new PR in the same window", function()
    greeter.open(win)
    local _, before = column()
    greeter.prs[root].pr = pr(3)
    greeter.redraw()
    local names, after = column()
    assert.equals("gh://o/r/pr/3", names[2])
    assert.equals(before[3], after[3])
  end)

  it("refreshes a PR rendered before when it comes back into the window", function()
    greeter.open(win)
    local _, wins = column()
    local attached = gh.attached[vim.api.nvim_win_get_buf(wins[2])]
    greeter.prs[root].pr = pr(3)
    greeter.redraw()
    greeter.prs[root].pr = pr(2)
    greeter.redraw()
    assert.equals(1, attached.updates)
  end)

  it("refreshes the PR when the branch's HEAD moves, and only then", function()
    greeter.open(win)
    local _, wins = column()
    local attached = gh.attached[vim.api.nvim_win_get_buf(wins[2])]
    greeter.cache_report(root, report("abc"), {})
    assert.equals(0, attached.updates)
    greeter.cache_report(root, report("def"), {})
    assert.equals(1, attached.updates)
  end)

  it("opens a stack row's PR in the browser with G", function()
    local opened
    vim.ui.open = function(path, _)
      opened = path
      return nil, nil
    end
    greeter.open(win)
    local _, wins = column()
    vim.api.nvim_win_call(wins[1], function()
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      vim.cmd("normal G")
    end)
    assert.equals("https://github.com/o/r/pull/1", opened)
  end)

  it("switches to the tab whose worktree has a stack row's branch with <cr>", function()
    local workspace = require("config.workspace")
    local find = workspace.find
    greeter.open(win)
    local _, wins = column()
    vim.cmd("tabnew")
    local other = vim.api.nvim_get_current_tabpage()
    vim.cmd("tabprevious")
    workspace.find = function(dir)
      return dir == repo .. "/wt-a" and other or nil
    end
    vim.api.nvim_win_call(wins[1], function()
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      vim.cmd("normal \r")
    end)
    local switched = vim.wait(2000, function()
      return vim.api.nvim_get_current_tabpage() == other
    end)
    workspace.find = find
    assert.is_true(switched)
  end)
end)
