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
    greeter.draw(buf, { { { "ab", "Comment" }, { "cd" } }, { { "e", "Special" } } })

    assert.same({ "abcd", "e" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    local marks = vim.tbl_map(function(m)
      return { m[2], m[3], m[4].end_col, m[4].hl_group }
    end, vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true }))
    assert.same({ { 0, 0, 2, "Comment" }, { 1, 0, 1, "Special" } }, marks)
    assert.is_false(vim.bo[buf].modifiable)
  end)
end)

describe("greeter.size_line", function()
  local function text(item)
    return table.concat(vim.tbl_map(function(c)
      return c[1]
    end, item.text))
  end

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

describe("greeter.stack_items", function()
  local function texts(items)
    return vim.tbl_map(function(item)
      return table.concat(vim.tbl_map(function(c)
        return c[1]
      end, item.text))
    end, items)
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
