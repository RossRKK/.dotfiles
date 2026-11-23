-- Layout decisions in config/greeter.lua that would otherwise show up as a
-- crowded or crooked greeter. Snacks is not run here: the sections are
-- inspected as data.

local assert = require("luassert")
local greeter = require("config.greeter")

describe("greeter.sections", function()
  it("starts with a blank line so Agents never touches the top edge", function()
    local sections = greeter.sections("/nowhere", 0, 0, function()
      return nil
    end)
    assert.same({ padding = 1 }, sections[1])
  end)

  it("gives each agent row's glyph the same width, so the rows line up", function()
    local real = package.loaded["fishmonger.view"]
    package.loaded["fishmonger.view"] = {
      items = function()
        return {
          { key = "a", icon = "⏳", hl = "Comment", project = "one" },
          { key = "s", icon = "✓", hl = "DiagnosticOk", project = "two" },
        }
      end,
    }
    local ok, section = pcall(greeter.sections("/nowhere", 0, 0, function()
      return nil
    end)[2])
    package.loaded["fishmonger.view"] = real
    assert(ok, section)

    assert.equals("⏳", section[1].icon[1])
    assert.equals(
      vim.fn.strdisplaywidth(section[1].icon[1]),
      vim.fn.strdisplaywidth(section[2].icon[1])
    )
  end)

  describe("the PR block", function()
    -- A real directory outside any repo: the queue line asks git about it.
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    local pr = { number = 42, title = "Make it faster", state = "OPEN", body = "" }
    local function first_line(branch)
      local pr_section = greeter.sections(root, 0, 0, function()
        return { branch = branch }
      end)[4]
      local items = pr_section()
      return items
        and table.concat(vim.tbl_map(function(c)
          return c[1]
        end, items[1].text))
    end
    after_each(function()
      greeter.prs[root] = nil
    end)

    it("shows the branch's PR outside review mode too", function()
      greeter.prs[root] = { branch = "feat", at = 0, pr = pr }
      assert.equals("#42 Make it faster", first_line("feat"))
    end)

    it("is absent when the branch has no PR", function()
      greeter.prs[root] = { branch = "feat", at = 0, pr = false }
      assert.is_nil(first_line("feat"))
    end)

    it("hides a PR fetched for the branch checked out before", function()
      greeter.prs[root] = { branch = "old", at = 0, pr = pr }
      assert.is_nil(first_line("feat"))
    end)
  end)
end)

-- Regression: a snacks dashboard's update() puts the cursor on an action item in
-- the window it opened in, without checking what that window shows now. Our
-- greeters stay alive after a file is opened over them, so refreshing a hidden
-- one used to yank the file's cursor.
describe("greeter.update_dashboards", function()
  local dash_buf, dash, updates

  -- A fresh, named-by-content buffer each time: `:enew` on an empty unnamed
  -- buffer reuses it, which would make the "file" and the dashboard one buffer.
  local function show_new_buffer(lines)
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_win_set_buf(0, buf)
    return buf
  end

  before_each(function()
    dash_buf = show_new_buffer({ "greeter" })
    updates = 0
    -- Stand-in for the object Snacks.dashboard.open() returns: remembers its
    -- window and, like snacks, moves that window's cursor when updated.
    dash = { win = vim.api.nvim_get_current_win() }
    function dash.update(self)
      updates = updates + 1
      vim.api.nvim_win_set_cursor(self.win, { 1, 0 })
    end
    greeter._instances[dash_buf] = dash
  end)

  after_each(function()
    greeter._instances[dash_buf] = nil
    vim.cmd("%bwipeout!")
  end)

  it("updates a dashboard that is shown in its own window", function()
    greeter.update_dashboards()
    assert.equals(1, updates)
  end)

  it("leaves the cursor alone once a file is opened over the dashboard", function()
    show_new_buffer({ "one", "two", "three" })
    vim.api.nvim_win_set_cursor(0, { 3, 2 })

    greeter.update_dashboards()

    assert.equals(0, updates)
    assert.same({ 3, 2 }, vim.api.nvim_win_get_cursor(0))
  end)

  it("forgets a dashboard whose buffer is gone", function()
    show_new_buffer({ "other" })
    vim.api.nvim_buf_delete(dash_buf, { force = true })
    greeter.update_dashboards()
    assert.is_nil(greeter._instances[dash_buf])
  end)
end)

-- Regression: snacks' own WinResized autocmd calls size() and, on a change,
-- update() -- which ends by setting the cursor in `self.win`. A hidden greeter
-- whose old window now shows a file made every split-resize either error
-- ("Invalid cursor line: out of range") or yank the file's cursor.
describe("greeter.patch_snacks_dashboard", function()
  local D, dash, dash_buf

  local function show_new_buffer(lines)
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_win_set_buf(0, buf)
    return buf
  end

  before_each(function()
    vim.cmd("only!")
    -- A stand-in for snacks.dashboard.Dashboard with the real size()/find()
    -- bodies: unguarded reads of self.win, and self.lines[row] without a check.
    D = {}
    D.__index = D
    function D:size()
      return {
        width = vim.api.nvim_win_get_width(self.win),
        height = vim.api.nvim_win_get_height(self.win),
      }
    end
    function D:find(pos)
      return { row = pos[1], text = self.lines[pos[1]]:sub(1, 1) }
    end
    greeter.patch_snacks_dashboard(D)

    dash_buf = show_new_buffer({ "greeter" })
    dash = setmetatable(
      { buf = dash_buf, win = vim.api.nvim_get_current_win(), lines = { "a", "b" } },
      D
    )
    dash._size = dash:size()
  end)

  after_each(function()
    vim.cmd("only!")
    vim.cmd("%bwipeout!")
  end)

  it("is idempotent", function()
    local size = D.size
    greeter.patch_snacks_dashboard(D)
    assert.equals(size, D.size)
  end)

  it("reports the live size while shown in its own window", function()
    vim.cmd("split")
    vim.cmd("wincmd j")
    assert.equals(vim.api.nvim_win_get_height(dash.win), dash:size().height)
  end)

  it(
    "reports the last size, unchanged, once a file is shown in its old window and it is resized",
    function()
      show_new_buffer({ "one" })
      vim.cmd("split") -- shrinks the old window: snacks would see a new size and update()
      assert.same(dash._size, dash:size())
    end
  )

  it("reports the last size when its window is gone", function()
    vim.cmd("split")
    vim.api.nvim_win_close(dash.win, true)
    assert.same(dash._size, dash:size())
  end)

  it("follows the buffer to the window that shows it now", function()
    show_new_buffer({ "one" })
    vim.cmd("split")
    vim.api.nvim_win_set_buf(0, dash_buf)
    local here = vim.api.nvim_get_current_win()
    assert.equals(vim.api.nvim_win_get_height(here), dash:size().height)
    assert.equals(here, dash.win)
  end)

  it("clamps find() to the rendered lines", function()
    assert.equals(2, dash:find({ 5, 0 }).row)
    dash.lines = {}
    assert.is_nil(dash:find({ 1, 0 }))
  end)
end)

describe("greeter.show_todo", function()
  local todo_file = vim.fs.normalize(vim.fn.tempname() .. "-todo.md")

  local function todo_windows()
    return #vim.tbl_filter(function(w)
      return vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w)) == todo_file
    end, vim.api.nvim_tabpage_list_wins(0))
  end

  after_each(function()
    vim.cmd("only!")
  end)

  it("opens the list below the greeter, keeping focus", function()
    local greeter_win = vim.api.nvim_get_current_win()
    greeter.show_todo(greeter_win, todo_file)
    assert.equals(1, todo_windows())
    assert.equals(greeter_win, vim.api.nvim_get_current_win())
    assert.is_false(vim.bo[vim.fn.bufnr(todo_file)].buflisted)
  end)

  it("does not stack a second list when the greeter is reopened", function()
    greeter.show_todo(vim.api.nvim_get_current_win(), todo_file)
    greeter.show_todo(vim.api.nvim_get_current_win(), todo_file)
    assert.equals(1, todo_windows())
  end)
end)

describe("greeter.wrap", function()
  it("wraps on word boundaries within the width", function()
    assert.same({ "aaa bbb", "ccc" }, greeter.wrap("aaa bbb ccc", 7))
  end)

  it("cuts a word longer than the line instead of overflowing", function()
    assert.same({ "see", "abcde", "fgh" }, greeter.wrap("see abcdefgh", 5))
  end)
end)

describe("greeter.pr_items", function()
  local function texts(items)
    return vim.tbl_map(function(item)
      return item.text
          and table.concat(vim.tbl_map(function(c)
            return c[1]
          end, type(item.text) == "string" and { { item.text } } or item.text))
        or "<pad>"
    end, items)
  end

  local pr = {
    number = 42,
    title = "Make it faster",
    state = "OPEN",
    isDraft = false,
    body = "<!-- template: delete me -->\r\n## Why\r\n\r\n\r\nBecause.\r\n  - a point\r\n",
  }

  it("leads with the number and title, then status, then the description as markdown", function()
    local items = greeter.pr_items(pr, 80, 10, 0)
    local t = texts(items)
    assert.equals("#42 Make it faster", t[1])
    assert.equals("open", t[2])
    assert.equals("<pad>", t[3])
    assert.same({ "## Why", "", "Because.", "  - a point" }, items[4].markdown)
  end)

  it("reserves a dashboard row for each row the description wraps to", function()
    local items =
      greeter.pr_items(vim.tbl_extend("force", pr, { body = "aaa bbb ccc\n\nddd" }), 10, 10, 0)
    -- "aaa bbb" / "ccc", the blank, "ddd": four rows, the text's three newlines.
    assert.equals("\n\n\n", items[4].text)
  end)

  it("strips template comments and collapses blank runs", function()
    for _, s in ipairs(greeter.pr_items(pr, 80, 10, 0)[4].markdown) do
      assert.is_nil(s:find("template", 1, true))
    end
  end)

  it("cuts a long description and counts the rest", function()
    local long = vim.tbl_extend("force", pr, { body = "one\ntwo\nthree\nfour" })
    local items = greeter.pr_items(long, 80, 2, 0)
    assert.equals("\n", items[4].text)
    assert.equals("\u{2026} 2 more lines", texts(items)[5])
  end)

  it("collapses a fenced block to one placeholder line", function()
    local fenced = vim.tbl_extend("force", pr, {
      body = "Intro\n```mermaid\nflowchart TB\n  a --> b\n```\nOutro\n~~~\nraw\n~~~",
    })
    assert.same(
      { "Intro", "_[mermaid block]_", "Outro", "_[code block]_" },
      greeter.pr_items(fenced, 80, 10, 0)[4].markdown
    )
  end)

  it("says so when there is no description", function()
    local t = texts(greeter.pr_items(vim.tbl_extend("force", pr, { body = "" }), 80, 5, 0))
    assert.equals("no description", t[4])
  end)
end)

-- The description is drawn by the real render-markdown, under this config's
-- opts, in a float over the rows the dashboard reserves for it.
describe("greeter's PR description", function()
  require("tests.helpers.plugins").add("render-markdown.nvim")
  local overlays = require("util.dashboard_markdown")._overlays
  local greeter_buf, win, dash, updates

  local function floats()
    return vim.tbl_filter(function(w)
      return vim.api.nvim_win_get_config(w).relative ~= ""
    end, vim.api.nvim_list_wins())
  end

  --- Draw the description item as snacks would, at row 2, column 4 of the greeter.
  local function draw(body)
    local pr = { number = 1, title = "t", state = "OPEN", body = body }
    greeter.pr_items(pr, 40, 10, greeter_buf)[4].render(dash, { 2, 3 })
    -- render() draws once snacks has written the rows.
    assert(vim.wait(1000, function()
      local overlay = overlays[greeter_buf]
      return overlay ~= nil
        and overlay.win ~= nil
        and vim.deep_equal(
          vim.api.nvim_buf_get_lines(overlay.buf, 0, -1, false),
          greeter.description(body)
        )
    end))
  end

  before_each(function()
    vim.cmd("runtime! plugin/render-markdown.lua")
    require("render-markdown").setup(require("plugins.render-markdown")[1].opts)
    greeter_buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_lines(greeter_buf, 0, -1, false, vim.fn["repeat"]({ "" }, 20))
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, greeter_buf)
    updates = 0
    dash = {
      win = win,
      update = function()
        updates = updates + 1
      end,
    }
  end)

  after_each(function()
    vim.cmd("%bwipeout!")
  end)

  it("is a markdown buffer that render-markdown renders, over the reserved rows", function()
    draw("## Why\n\nIt is **much** faster.")
    local float = assert(floats()[1])
    local buf = vim.api.nvim_win_get_buf(float)
    assert.equals("markdown", vim.bo[buf].filetype)
    assert.same(
      { "## Why", "", "It is **much** faster." },
      vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    )
    local config = vim.api.nvim_win_get_config(float)
    assert.same(
      { win, 40, 3, false },
      { config.win, config.width, config.height, config.focusable }
    )
    -- At the greeter's row 2, column 5, where snacks put the reserved rows' first line.
    vim.cmd.redraw()
    local at = vim.fn.screenpos(win, 2, 5)
    assert.same({ at.row, at.col }, vim.fn.win_screenpos(float))
    local ns = vim.api.nvim_get_namespaces()["render-markdown.nvim"]
    assert(
      vim.wait(1000, function()
        return #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) > 0
      end),
      "render-markdown drew nothing"
    )
    -- The bold's asterisks are concealed: rendered, not raw.
    assert.equals(3, vim.wo[float].conceallevel)
  end)

  it("moves its one float on a redraw rather than stacking another", function()
    draw("one")
    draw("two")
    assert.equals(1, #floats())
    assert.same(
      { "two" },
      vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(floats()[1]), 0, -1, false)
    )
  end)

  it("goes when the greeter is hidden and is redrawn when it is shown again", function()
    draw("one")
    vim.api.nvim_win_set_buf(win, vim.api.nvim_create_buf(true, false))
    assert.equals(0, #floats())

    vim.api.nvim_win_set_buf(win, greeter_buf)
    assert(vim.wait(1000, function()
      return updates == 1
    end))
  end)

  it("goes when the greeter draws no description", function()
    draw("one")
    require("util.dashboard_markdown").close(greeter_buf)
    assert.equals(0, #floats())
  end)

  it("frees its markdown buffer with the greeter", function()
    draw("one")
    local buf = overlays[greeter_buf].buf
    vim.api.nvim_buf_delete(greeter_buf, { force = true })
    assert.is_false(vim.api.nvim_buf_is_valid(buf))
    assert.equals(0, #floats())
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

describe("greeter.by_tier", function()
  local function rels(files)
    return vim.tbl_map(function(f)
      return f.rel
    end, files)
  end

  it("orders spec, proto, code, test, docs, generated, keeping the order within a tier", function()
    local files = vim.tbl_map(function(rel)
      return { rel = rel }
    end, {
      "Cargo.lock",
      "README.md",
      "src/b.rs",
      "src/a_test.rs",
      "api.proto",
      "src/a.rs",
      "SPEC.md",
      "z/tests/x.lua",
      "a/tests/y.lua",
    })
    assert.same({
      "SPEC.md",
      "api.proto",
      "src/b.rs",
      "src/a.rs",
      "src/a_test.rs",
      "z/tests/x.lua",
      "a/tests/y.lua",
      "README.md",
      "Cargo.lock",
    }, rels(greeter.by_tier(files, {})))
  end)

  it("tiers a file by its attributes", function()
    local files = { { rel = "gen/a.rs" }, { rel = "b.rs" } }
    assert.same(
      { "b.rs", "gen/a.rs" },
      rels(greeter.by_tier(files, { ["gen/a.rs"] = { generated = true } }))
    )
  end)
end)

describe("greeter.pr_status", function()
  local function text(pr)
    return table.concat(vim.tbl_map(function(c)
      return c[1]
    end, greeter.pr_status(pr)))
  end

  it("calls an open draft a draft", function()
    assert.equals("draft", text({ state = "OPEN", isDraft = true }))
  end)

  it("adds the review decision only when GitHub has one", function()
    assert.equals(
      "open  \u{00b7}  changes requested",
      text({ state = "OPEN", reviewDecision = "CHANGES_REQUESTED" })
    )
    assert.equals("open", text({ state = "OPEN" }))
  end)

  -- The rollup goes through the review queue's reading, so the greeter and
  -- <leader>rm agree on what's failing.
  local done = { name = "lint", status = "COMPLETED", conclusion = "SUCCESS" }
  local skipped = { name = "docs", status = "COMPLETED", conclusion = "SKIPPED" }
  local running = { name = "build", status = "IN_PROGRESS" }
  local failed = { name = "test", status = "COMPLETED", conclusion = "FAILURE" }
  local legacy_pending = { context = "ci/legacy", state = "PENDING" }
  local gate = {
    name = "Mergify Merge Protections",
    status = "COMPLETED",
    conclusion = "FAILURE",
    checkSuite = { app = { slug = "mergify" } },
  }
  for _, case in ipairs({
    {
      "passes when nothing failed or is running",
      "SUCCESS",
      { done, skipped },
      "\u{2713} checks pass",
    },
    { "counts what's pending", "PENDING", { done, running, legacy_pending }, "\u{25cf} 2 pending" },
    { "lets any failure win", "FAILURE", { running, failed }, "\u{2717} 1 failing" },
    { "leaves Mergify's review gate out", "FAILURE", { done, gate }, "\u{2713} checks pass" },
    {
      "still counts CI failing beside the gate",
      "FAILURE",
      { gate, failed },
      "\u{2717} 1 failing",
    },
  }) do
    it("summarises checks: " .. case[1], function()
      local rollup = { state = case[2], contexts = { nodes = case[3] } }
      local checks = require("util.reviewqueue").checks_of(rollup)
      assert.equals("open  \u{00b7}  " .. case[4], text({ state = "OPEN", checks = checks }))
    end)
  end

  it("says nothing about checks before they've been fetched", function()
    assert.equals("open", text({ state = "OPEN" }))
  end)
end)

describe("greeter.queue_line", function()
  local function text(item)
    return table.concat(vim.tbl_map(function(c)
      return c[1]
    end, item.text))
  end

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
  local function text(item)
    return table.concat(vim.tbl_map(function(c)
      return c[1]
    end, item.text))
  end

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

describe("greeter.sections' stack", function()
  local rq = require("util.reviewqueue")
  local saved_key
  before_each(function()
    saved_key = rq.key
    rq.key = function()
      return "/repo"
    end
  end)
  after_each(function()
    rq.cache = {}
    rq.key = saved_key
  end)

  local function stack_section(branch)
    return greeter
      .sections("/repo", 0, 0, function()
        return { branch = branch }
      end)
      [5]()
  end
  local function mine(number, head, base)
    return { pr = { number = number, title = "", head = head, base = base }, verdict = { tier = 5 } }
  end

  it("shows the stack the branch's PR is in under a Stack title", function()
    rq.cache["/repo"] = { mine = { mine(1, "a", "main"), mine(2, "b", "a") } }
    local section = stack_section("b")
    assert.equals("Stack", section.title)
    assert.equals(3, #section)
  end)

  it("is absent before the queue has listed my PRs, or for a lone PR", function()
    assert.is_nil(stack_section("b"))
    rq.cache["/repo"] = { mine = { mine(1, "a", "main") } }
    assert.is_nil(stack_section("a"))
  end)
end)
