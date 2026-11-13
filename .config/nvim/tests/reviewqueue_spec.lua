-- The "does this PR actually need me" decisions in util/reviewqueue.lua:
-- CODEOWNERS matching and PR classification. The GitHub side is left to the
-- real thing; these are the parts that go wrong silently -- a PR wrongly
-- hidden is never noticed.

local assert = require("luassert")
local rq = require("util.reviewqueue")

describe("reviewqueue.glob_match", function()
  local m = rq.glob_match

  -- The examples from GitHub's CODEOWNERS documentation.
  it("matches * against every file", function()
    assert.is_true(m("*", "a.txt"))
    assert.is_true(m("*", "deep/down/a.txt"))
  end)

  it("matches an unanchored extension at any depth", function()
    assert.is_true(m("*.js", "app.js"))
    assert.is_true(m("*.js", "src/lib/app.js"))
    assert.is_false(m("*.js", "src/app.jsx"))
  end)

  it("matches an unanchored directory at any depth", function()
    assert.is_true(m("apps/", "apps/x.go"))
    assert.is_true(m("apps/", "nested/apps/x.go"))
    assert.is_false(m("apps/", "apps")) -- trailing slash: directories only
  end)

  it("owns everything under an anchored directory, with or without a slash", function()
    assert.is_true(m("/build/logs/", "build/logs/a/b.log"))
    assert.is_true(m("/build/logs", "build/logs/a/b.log"))
    assert.is_false(m("/build/logs", "other/build/logs/a.log"))
  end)

  it("treats an inner slash as anchoring", function()
    assert.is_true(m("docs/guide", "docs/guide/a.md"))
    assert.is_false(m("docs/guide", "x/docs/guide/a.md"))
  end)

  it("limits a trailing /* to direct children", function()
    assert.is_true(m("docs/*", "docs/getting-started.md"))
    assert.is_false(m("docs/*", "docs/build-app/troubleshooting.md"))
  end)

  it("lets ** span zero or more directories", function()
    assert.is_true(m("/proj/**/Cargo.toml", "proj/Cargo.toml"))
    assert.is_true(m("/proj/**/Cargo.toml", "proj/a/b/Cargo.toml"))
    assert.is_false(m("/proj/**/Cargo.toml", "proj/a/Cargo.lock"))
    assert.is_true(m("/proj/**", "proj/a/b"))
  end)

  it("does not let a segment match a prefix of a name", function()
    assert.is_false(m("/src/app", "src/application/x.lua"))
  end)

  it("treats pattern magic characters literally", function()
    assert.is_true(m("/a-b.c", "a-b.c"))
    assert.is_false(m("/a-b.c", "a-bxc"))
  end)
end)

describe("reviewqueue.parse_codeowners / owners", function()
  local rules = rq.parse_codeowners(table.concat({
    "# a comment",
    "",
    "*                 @acme/everyone",
    "/svc/            @acme/Platform @Alice  # inline comment",
    "/svc/vendored/",
    "/svc/api.proto   @acme/platform @acme/api someone@example.com",
    "/with\\ space     @bob",
  }, "\n"))

  it("skips comments and blank lines, lowercases owners, drops emails", function()
    assert.equals(5, #rules)
    assert.same({ "acme/platform", "alice" }, rules[2].owners)
    assert.same({ "acme/platform", "acme/api" }, rules[4].owners)
  end)

  it("lets the last matching rule win", function()
    assert.same({ "acme/everyone" }, rq.owners(rules, "README.md"))
    assert.same({ "acme/platform", "alice" }, rq.owners(rules, "svc/main.go"))
    assert.same({ "acme/platform", "acme/api" }, rq.owners(rules, "svc/api.proto"))
  end)

  it("lets an ownerless rule un-own a path", function()
    assert.same({}, rq.owners(rules, "svc/vendored/lib.go"))
  end)

  it("unescapes spaces in paths", function()
    assert.same({ "bob" }, rq.owners(rules, "with space/x"))
  end)
end)

describe("reviewqueue.classify", function()
  local rules = rq.parse_codeowners(table.concat({
    "*        @acme/everyone",
    "/svc/    @acme/platform",
    "/web/    @acme/frontend",
    "/shared/ @acme/platform @acme/frontend",
  }, "\n"))

  ---@return reviewqueue.Ctx
  local function ctx(over)
    return vim.tbl_extend("force", {
      me = "Me",
      my_teams = { ["acme/platform"] = true, ["acme/everyone"] = true },
      exclude = { ["acme/everyone"] = true },
      rules = rules,
      teams_of = {
        me = { ["acme/platform"] = true, ["acme/everyone"] = true },
        pat = { ["acme/platform"] = true, ["acme/everyone"] = true },
        fran = { ["acme/frontend"] = true, ["acme/everyone"] = true },
        eve = { ["acme/everyone"] = true },
      },
    }, over or {})
  end

  ---@return reviewqueue.PR
  local function pr(over)
    return vim.tbl_extend("force", {
      number = 1,
      title = "t",
      url = "u",
      author = "someone",
      draft = false,
      head = "feat",
      base = "main",
      head_oid = "HEAD2",
      cross_repo = false,
      user_requests = { "me" },
      team_requests = { "acme/platform" },
      reviews = {},
      files = { "svc/main.go" },
    }, over or {})
  end

  local function tier(p, c)
    local v = rq.classify(pr(p), ctx(c))
    return v and v.tier
  end

  it("needs me when named and nobody on my team has approved", function()
    local v = rq.classify(pr(), ctx())
    assert.equals(1, v.tier)
    assert.matches("acme/platform", v.reason)
  end)

  it("compares logins case-insensitively", function()
    assert.equals(1, tier({ user_requests = { "ME" } }))
  end)

  it("skips my own PRs and drafts", function()
    assert.is_nil(tier({ author = "me" }))
    assert.is_nil(tier({ draft = true }))
  end)

  it("drops a PR once a teammate's approval covers every file I own", function()
    assert.is_nil(tier({ reviews = { { author = "pat", state = "APPROVED", commit = "HEAD2" } } }))
  end)

  it("ignores approvals from people who don't own the file", function()
    assert.equals(
      1,
      tier({ reviews = { { author = "fran", state = "APPROVED", commit = "HEAD2" } } })
    )
  end)

  it("counts any owner of a jointly-owned file as covering it", function()
    -- /shared/ is platform OR frontend: frontend's approval is enough.
    assert.is_nil(tier({
      files = { "shared/x" },
      reviews = { { author = "fran", state = "APPROVED", commit = "HEAD2" } },
    }))
  end)

  it("keeps a PR while ANY file I own is uncovered", function()
    assert.equals(
      1,
      tier({
        files = { "shared/x", "svc/y" },
        reviews = { { author = "fran", state = "APPROVED", commit = "HEAD2" } },
      })
    )
  end)

  it("ignores dismissed approvals", function()
    assert.equals(
      1,
      tier({ reviews = { { author = "pat", state = "DISMISSED", commit = "HEAD2" } } })
    )
  end)

  it("puts a team-only request in the team tier", function()
    assert.equals(3, tier({ user_requests = {} }))
  end)

  it("drops a team-only request via an excluded team", function()
    assert.is_nil(
      tier({ user_requests = {}, files = { "README.md" }, team_requests = { "acme/everyone" } })
    )
  end)

  it("keeps an excluded team's files when I'm named", function()
    local v = rq.classify(pr({ files = { "README.md" } }), ctx())
    assert.equals(1, v.tier)
    assert.matches("acme/everyone", v.reason)
  end)

  it("names the real team, not the excluded one, when both apply", function()
    local p = pr({ files = { "README.md", "svc/a" } })
    local v = rq.classify(p, ctx())
    assert.equals("owns unapproved files via acme/platform", v.reason)
  end)

  it("drops a PR I've reviewed at its current head", function()
    assert.is_nil(tier({ reviews = { { author = "me", state = "APPROVED", commit = "HEAD2" } } }))
    assert.is_nil(
      tier({ reviews = { { author = "me", state = "CHANGES_REQUESTED", commit = "HEAD2" } } })
    )
  end)

  it("brings back a change request that new commits overtook", function()
    local v = rq.classify(
      pr({ reviews = { { author = "me", state = "CHANGES_REQUESTED", commit = "HEAD1" } } }),
      ctx()
    )
    assert.equals(2, v.tier)
  end)

  it("leaves a stale approval alone unless re-requested", function()
    local stale = { { author = "me", state = "APPROVED", commit = "HEAD1" } }
    assert.is_nil(tier({ reviews = stale, user_requests = {} }))
    assert.equals(2, tier({ reviews = stale }))
  end)

  it("treats a dismissed review of mine as no review", function()
    assert.equals(
      1,
      tier({ reviews = { { author = "me", state = "DISMISSED", commit = "HEAD2" } } })
    )
  end)

  it("still needs me after a comment-only review removed my request", function()
    assert.equals(1, tier({ user_requests = {}, reviewed_by_me = true }))
  end)

  it("keeps a by-name request when I own nothing in the PR", function()
    local v = rq.classify(pr({ files = { "web/x" } }), ctx({ exclude = {} }))
    assert.equals(1, v.tier)
    assert.equals("requested by name", v.reason)
  end)

  it("drops a by-name request whose files are all covered by others", function()
    assert.is_nil(tier({
      files = { "web/x", "svc/y" },
      reviews = {
        { author = "pat", state = "APPROVED", commit = "HEAD1" },
      },
    }))
  end)

  it("does not resurrect a comment on a PR I own nothing in", function()
    assert.is_nil(tier({ user_requests = {}, reviewed_by_me = true, files = { "web/x" } }))
  end)
end)

describe("reviewqueue.team_set", function()
  it("includes ancestors, lowercased", function()
    local set = rq.team_set({
      nodes = {
        {
          combinedSlug = "Acme/Child",
          ancestors = { nodes = { { combinedSlug = "Acme/Parent" } } },
        },
      },
    })
    assert.same({ ["acme/child"] = true, ["acme/parent"] = true }, set)
  end)
end)

describe("reviewqueue.from_node", function()
  it("splits user and team requests and tolerates missing fields", function()
    local p = rq.from_node({
      number = 7,
      headRefOid = "abc",
      author = nil, -- deleted account
      reviewRequests = {
        nodes = {
          { requestedReviewer = { login = "me" } },
          { requestedReviewer = { combinedSlug = "acme/platform" } },
          { requestedReviewer = {} }, -- a bot/mannequin with neither field
        },
      },
      latestOpinionatedReviews = {
        nodes = { { state = "APPROVED", author = { login = "pat" }, commit = { oid = "abc" } } },
      },
      files = { nodes = { { path = "a", additions = 3, deletions = 1 }, { path = "b" } } },
    }, true)
    assert.equals("ghost", p.author)
    assert.same({ "me" }, p.user_requests)
    assert.same({ "acme/platform" }, p.team_requests)
    assert.same({ { author = "pat", state = "APPROVED", commit = "abc" } }, p.reviews)
    assert.same({ "a", "b" }, p.files)
    assert.same({
      { path = "a", additions = 3, deletions = 1 },
      { path = "b", additions = 0, deletions = 0 },
    }, p.changes)
    assert.is_true(p.reviewed_by_me)
  end)
end)

describe("reviewqueue.depends_on", function()
  local repo = { owner = "Acme", name = "app" }
  for _, case in ipairs({
    { "#123", "Depends-On: #123", { { owner = "Acme", name = "app", number = 123 } } },
    {
      "a PR URL",
      "Depends-On: https://github.com/acme/lib/pull/9",
      { { owner = "acme", name = "lib", number = 9 } },
    },
    { "org/repo#123", "Depends-On: acme/lib#9", { { owner = "acme", name = "lib", number = 9 } } },
    {
      "any case, padding and CRLF",
      "intro\r\n  depends-on:   #4  \r\nDEPENDS-ON: #5\r\n",
      { { owner = "Acme", name = "app", number = 4 }, { owner = "Acme", name = "app", number = 5 } },
    },
    { "nothing but the reference on the line", "Depends-On: #4 (the proto)", {} },
    { "the header at the start of the line", "This depends-on: #4", {} },
    { "not a mention in prose", "depends on #4", {} },
    { "no body", nil, {} },
  }) do
    it("reads " .. case[1], function()
      assert.same(case[3], rq.depends_on(case[2], repo))
    end)
  end

  it("is read off a PR node against its own repo", function()
    local p = rq.from_node({ number = 2, body = "Depends-On: #1" }, false, repo)
    assert.same({ { owner = "Acme", name = "app", number = 1 } }, p.depends_on)
  end)
end)

describe("reviewqueue.sort", function()
  it("orders by tier, then newest PR first", function()
    local items = rq.sort({
      { pr = { number = 1 }, verdict = { tier = 3 } },
      { pr = { number = 2 }, verdict = { tier = 1 } },
      { pr = { number = 5 }, verdict = { tier = 1 } },
    })
    assert.same(
      { 5, 2, 1 },
      vim.tbl_map(function(i)
        return i.pr.number
      end, items)
    )
  end)
end)

describe("reviewqueue.classify_mine", function()
  local rules = rq.parse_codeowners(table.concat({
    "/svc/    @acme/platform",
    "/web/    @acme/frontend",
  }, "\n"))

  ---@return reviewqueue.MineCtx
  local function ctx(over)
    return vim.tbl_extend("force", {
      me = "Me",
      my_teams = {},
      exclude = {},
      rules = rules,
      teams_of = {
        pat = { ["acme/platform"] = true },
        fran = { ["acme/frontend"] = true },
      },
      default_branch = "main",
      heads = { ["feat-1"] = 41 },
      repo = { owner = "Acme", name = "app" },
      open_refs = {},
    }, over or {})
  end

  ---@return reviewqueue.PR
  local function pr(over)
    return vim.tbl_extend("force", {
      number = 42,
      title = "t",
      url = "u",
      author = "me",
      draft = false,
      head = "feat-2",
      base = "main",
      head_oid = "HEAD",
      cross_repo = false,
      depends_on = {},
      user_requests = {},
      team_requests = {},
      reviews = {},
      files = { "svc/main.go" },
      changes = {},
      checks = "SUCCESS",
      failing = {},
      threads = {},
      auto_merge = false,
    }, over or {})
  end

  local approved = { { author = "pat", state = "APPROVED" } }

  local function verdict(p, c)
    local v = rq.classify_mine(pr(p), ctx(c))
    return v.tier, v.reason
  end

  it("is ready to merge once a code owner of every file approves", function()
    assert.same({ 2, "approved" }, { verdict({ reviews = approved }) })
  end)

  it("names the owners still missing", function()
    assert.same(
      { 5, "approved, awaiting acme/frontend" },
      { verdict({ reviews = approved, files = { "svc/a.go", "web/b.ts" } }) }
    )
    -- An approval from someone who owns nothing here doesn't count.
    assert.same(
      { 5, "approved, awaiting acme/platform" },
      { verdict({ reviews = { { author = "fran", state = "APPROVED" } } }) }
    )
    assert.same({ 5, "awaiting acme/platform" }, { verdict({}) })
  end)

  it("needs one approval even when nothing is owned", function()
    assert.same({ 5, "awaiting review" }, { verdict({ files = { "README.md" } }) })
    assert.same(
      { 2, "approved" },
      { verdict({ files = { "README.md" }, reviews = { { author = "eve", state = "APPROVED" } } }) }
    )
  end)

  it("ignores my own review", function()
    assert.same({ 5, "awaiting acme/platform" }, {
      verdict(
        { reviews = { { author = "ME", state = "APPROVED" } } },
        { teams_of = { me = { ["acme/platform"] = true } } }
      ),
    })
  end)

  it("puts an approved stacked PR behind the one below it", function()
    assert.same(
      { 5, "approved, stacked on #41" },
      { verdict({ reviews = approved, base = "feat-1" }) }
    )
    assert.same(
      { 5, "approved, stacked on release" },
      { verdict({ reviews = approved, base = "release" }) }
    )
  end)

  -- Mergify holds a PR until every PR its Depends-On lines name has merged.
  local dep = { owner = "Acme", name = "app", number = 50 }
  local other_repo = { owner = "acme", name = "lib", number = 7 }
  for _, case in ipairs({
    { "an open dependency stacks it", { dep }, { "acme/app#50" }, "main", "approved, stacked on #50" },
    { "a merged or closed dependency doesn't", { dep }, {}, "main", "approved" },
    { "another repo's dependency is named in full", { other_repo }, { "acme/lib#7" }, "main", "approved, stacked on acme/lib#7" },
    { "the branch below comes first", { dep }, { "acme/app#50" }, "feat-1", "approved, stacked on #41, #50" },
    {
      "a dependency on the branch below is said once",
      { { owner = "acme", name = "APP", number = 41 } },
      { "acme/app#41" },
      "feat-1",
      "approved, stacked on #41",
    },
  }) do
    it("Depends-On: " .. case[1], function()
      local open = {}
      for _, key in ipairs(case[3]) do
        open[key] = true
      end
      local tier, reason = verdict(
        { reviews = approved, depends_on = case[2], base = case[4] },
        { open_refs = open }
      )
      assert.same({ #case[3] > 0 and 5 or 2, case[5] }, { tier, reason })
    end)
  end

  it("says what's still in the way of an approved PR", function()
    assert.same(
      { 2, "approved, checks pending, behind main" },
      { verdict({ reviews = approved, checks = "PENDING", merge_state = "BEHIND" }) }
    )
  end)

  it("lists everything to fix, and that trumps approval", function()
    local v = rq.classify_mine(
      pr({
        reviews = { approved[1], { author = "fran", state = "CHANGES_REQUESTED" } },
        checks = "FAILURE",
        failing = { "lint", "test" },
        mergeable = "CONFLICTING",
        threads = {
          { resolved = false, outdated = false, last = "pat" },
          { resolved = false, outdated = false, last = "fran" },
          { resolved = false, outdated = false, last = "me" }, -- answered, still open
          { resolved = true, outdated = false, last = "pat" },
        },
      }),
      ctx()
    )
    assert.equals(1, v.tier)
    assert.equals(
      "checks failing, changes requested by @fran, 2 unanswered threads, merge conflicts, 1 thread to resolve",
      v.reason
    )
    assert.same({ "failing: lint, test" }, v.notes)
    assert.is_true(v.review)
  end)

  it("only opens review mode when there are threads to answer or resolve", function()
    assert.is_false(rq.classify_mine(pr({ checks = "ERROR" }), ctx()).review)
    assert.is_true(
      rq.classify_mine(
        pr({ threads = { { resolved = false, outdated = false, last = "pat" } } }),
        ctx()
      ).review
    )
    assert.is_true(
      rq.classify_mine(
        pr({ threads = { { resolved = false, outdated = false, last = "me" } } }),
        ctx()
      ).review
    )
  end)

  it("opens mine with comments shown only when there are threads to answer", function()
    assert.equals("answer", rq.open_mode(true, { tier = 1, reason = "", review = true }))
    assert.equals("browse", rq.open_mode(true, { tier = 1, reason = "" }))
    assert.equals("review", rq.open_mode(false, { tier = 1, reason = "" }))
  end)

  it("leaves threads I've answered or that went outdated as loose ends", function()
    assert.same({ 3, "2 threads to resolve (1 outdated)" }, {
      verdict({
        reviews = approved,
        threads = {
          { resolved = false, outdated = false, last = "Me" },
          { resolved = false, outdated = true, last = "pat" }, -- the code moved on under it
          { resolved = true, outdated = true, last = "pat" },
        },
      }),
    })
  end)

  it("shows queued and auto-merging PRs as on their way", function()
    assert.same(
      { 4, "#4 in the merge queue, awaiting checks" },
      { verdict({ reviews = approved, queue = { state = "AWAITING_CHECKS", position = 4 } }) }
    )
    assert.same({ 4, "auto-merge on" }, { verdict({ auto_merge = true }) })
    -- Mergify's queue says neither where nor in what state.
    assert.same({ 4, "in the merge queue" }, { verdict({ reviews = approved, queue = {} }) })
    -- It lands without me: an open thread I've answered doesn't hold it up.
    assert.same({ 4, "#1 in the merge queue, queued" }, {
      verdict({
        queue = { state = "QUEUED", position = 1 },
        threads = { { resolved = false, outdated = false, last = "me" } },
      }),
    })
  end)

  it("flags a PR the merge queue threw out, unless I took it out", function()
    assert.same(
      { 1, "unmergeable in the merge queue" },
      { verdict({ queue = { state = "UNMERGEABLE", position = 1 } }) }
    )
    assert.same(
      { 1, "removed from the merge queue: failed_checks" },
      { verdict({ reviews = approved, dequeued = { reason = "FAILED_CHECKS", by = "github" } }) }
    )
    assert.same(
      { 2, "approved" },
      { verdict({ reviews = approved, dequeued = { reason = "", by = "Me" } }) }
    )
  end)

  it("counts a draft as unfinished, saying what else is wrong with it", function()
    assert.same({ 3, "draft, checks failing" }, { verdict({ draft = true, checks = "FAILURE" }) })
    assert.same({ 3, "draft" }, { verdict({ draft = true, reviews = approved }) })
  end)
end)

describe("reviewqueue.from_node (my PRs)", function()
  it("reads checks, threads and the merge queue", function()
    local p = rq.from_node({
      number = 7,
      mergeable = "CONFLICTING",
      mergeStateStatus = "BEHIND",
      autoMergeRequest = { enabledAt = "x" },
      mergeQueueEntry = { state = "QUEUED", position = 2 },
      timelineItems = {
        nodes = {
          { __typename = "RemovedFromMergeQueueEvent", reason = "x", actor = { login = "bot" } },
        },
      },
      reviewThreads = {
        nodes = {
          { isResolved = false, comments = { nodes = { { author = { login = "pat" } } } } },
          { isResolved = true, isOutdated = true, comments = { nodes = {} } },
        },
      },
      commits = {
        nodes = {
          {
            commit = {
              statusCheckRollup = {
                state = "FAILURE",
                contexts = {
                  nodes = {
                    { name = "lint", conclusion = "SUCCESS" },
                    { name = "test", conclusion = "TIMED_OUT" },
                    { context = "ci/legacy", state = "ERROR" },
                    { name = "test", conclusion = "FAILURE" }, -- same job, another workflow
                    {}, -- a context type the fragment doesn't cover
                  },
                },
              },
            },
          },
        },
      },
    }, false)
    assert.equals("CONFLICTING", p.mergeable)
    assert.equals("BEHIND", p.merge_state)
    assert.is_true(p.auto_merge)
    assert.same({ state = "QUEUED", position = 2 }, p.queue)
    assert.same({ reason = "x", by = "bot" }, p.dequeued)
    assert.same({
      { resolved = false, outdated = false, last = "pat" },
      { resolved = true, outdated = true },
    }, p.threads)
    assert.equals("FAILURE", p.checks)
    assert.same({ "test", "ci/legacy" }, p.failing)
  end)

  -- Mergify's queue leaves mergeQueueEntry null; its "queued" label marks it.
  for _, case in ipairs({
    { "Mergify's queued label", nil, { "queued" }, {} },
    { "GitHub's entry over the label", { state = "QUEUED", position = 2 }, { "queued" }, { state = "QUEUED", position = 2 } },
    { "Mergify's dequeued label isn't queued", nil, { "dequeued" }, nil },
    { "another label isn't queued", nil, { "queue" }, nil },
  }) do
    it("reads a merge queue from " .. case[1], function()
      local labels = vim.tbl_map(function(name)
        return { name = name }
      end, case[3])
      local p = rq.from_node({ number = 1, mergeQueueEntry = case[2], labels = { nodes = labels } }, false)
      assert.same(case[4], p.queue)
    end)
  end

  it("leaves a review-queue node (no such fields) with nothing to report", function()
    local p = rq.from_node({ number = 1 }, false)
    assert.is_nil(p.checks)
    assert.is_nil(p.queue)
    assert.is_nil(p.dequeued)
    assert.is_false(p.auto_merge)
    assert.same({}, p.threads)
    assert.same({}, p.failing)
  end)

  -- Mergify's review gate fails every unapproved PR; any other Mergify check,
  -- or another app's check of the same name, is a real result.
  local function mergify(name, conclusion)
    return { name = name, conclusion = conclusion, checkSuite = { app = { slug = "mergify" } } }
  end
  local gate = mergify("Mergify Merge Protections", "FAILURE")
  local impostor = {
    name = "Mergify Merge Protections",
    conclusion = "FAILURE",
    checkSuite = { app = { slug = "impostor" } },
  }
  for _, case in ipairs({
    { "only the gate failing passes", { gate }, "SUCCESS", {} },
    {
      "only the gate failing, CI still running, is pending",
      { gate, { name = "test", status = "IN_PROGRESS" } },
      "PENDING",
      {},
    },
    {
      "only the gate failing, a legacy status pending, is pending",
      { gate, { context = "ci/legacy", state = "PENDING" } },
      "PENDING",
      {},
    },
    {
      "CI failing alongside the gate fails",
      { gate, { name = "test", status = "COMPLETED", conclusion = "FAILURE" } },
      "FAILURE",
      { "test" },
    },
    {
      "another Mergify check failing fails",
      { gate, mergify("Mergify Merge Queue", "FAILURE") },
      "FAILURE",
      { "Mergify Merge Queue" },
    },
    { "the gate's name from another app fails", { impostor }, "FAILURE", { "Mergify Merge Protections" } },
  }) do
    it(case[1], function()
      local rollup = { state = "FAILURE", contexts = { nodes = case[2] } }
      local p = rq.from_node({ number = 1, commits = { nodes = { { commit = { statusCheckRollup = rollup } } } } }, false)
      assert.same({ case[3], case[4] }, { p.checks, p.failing })
    end)
  end
end)

describe("reviewqueue.counts_of", function()
  it("counts each list by its own tiers", function()
    local entry = {
      at = 0,
      items = { { pr = {}, verdict = { tier = 1 } } },
      mine = { { pr = {}, verdict = { tier = 5 } }, { pr = {}, verdict = { tier = 2 } } },
    }
    assert.same({ 1, 0, 0 }, rq.counts_of(entry))
    assert.same({ 0, 1, 0, 0, 1 }, rq.counts_of(entry, "mine"))
    assert.is_nil(rq.counts_of({ at = 0 }, "mine"))
  end)
end)

describe("reviewqueue.pick", function()
  local saved_snacks, saved_open, saved_key, opts, opened

  before_each(function()
    saved_snacks, saved_open, saved_key = _G.Snacks, vim.ui.open, rq.key
    opts, opened = nil, nil
    _G.Snacks = { picker = { pick = function(o)
      opts = o
    end } }
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.ui.open = function(path, _)
      opened = path
      return nil, nil
    end
    rq.key = function(_)
      return "repo"
    end
    local pr = { number = 7, title = "t", author = "me", head = "h", base = "main", url = "https://pr/7" }
    rq.cache.repo = {
      at = vim.uv.now(),
      repo = { owner = "o", name = "n" },
      items = { { pr = pr, verdict = { tier = 1, reason = "r" } } },
      mine = { { pr = pr, verdict = { tier = 1, reason = "r" } } },
    }
  end)

  after_each(function()
    _G.Snacks, vim.ui.open, rq.key = saved_snacks, saved_open, saved_key
    rq.cache.repo = nil
  end)

  for _, list in ipairs({ "items", "mine" }) do
    it(("opens the PR in the browser on normal-mode G in either window (%s)"):format(list), function()
      rq.pick(list)
      for _, win in ipairs({ "input", "list" }) do
        local key = opts.win[win].keys.G
        assert.equals("n", key.mode)
        opened = nil
        opts.actions[key[1]](nil, { pr = { url = "https://pr/7" } })
        assert.equals("https://pr/7", opened)
      end
    end)
  end
end)

describe("reviewqueue.refresh", function()
  local saved_key, saved_fetch, tiers, changes, listener

  before_each(function()
    saved_key, saved_fetch = rq.key, rq.fetch
    rq.key = function(_)
      return "refresh-spec"
    end
    rq.fetch = function(_)
      return vim.tbl_map(function(tier)
        return { verdict = { tier = tier } }
      end, tiers), nil, {}
    end
    changes = 0
    listener = vim.api.nvim_create_autocmd("User", {
      pattern = "ReviewQueueChanged",
      callback = function()
        changes = changes + 1
      end,
    })
  end)

  after_each(function()
    rq.key, rq.fetch = saved_key, saved_fetch
    rq.cache["refresh-spec"] = nil
    vim.api.nvim_del_autocmd(listener)
  end)

  it("announces a change in the counts, and stays quiet when they hold", function()
    tiers = { 1 }
    rq.refresh("/repo")
    assert.equals(1, changes)
    rq.refresh("/repo")
    assert.equals(1, changes)
    tiers = { 1, 2 }
    rq.refresh("/repo")
    assert.equals(2, changes)
  end)
end)
