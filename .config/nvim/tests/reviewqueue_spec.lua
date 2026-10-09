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

describe("reviewqueue.sort", function()
  it("orders by tier, then oldest PR first", function()
    local items = rq.sort({
      { pr = { number = 1 }, verdict = { tier = 3 } },
      { pr = { number = 2 }, verdict = { tier = 1 } },
      { pr = { number = 5 }, verdict = { tier = 1 } },
    })
    assert.same(
      { 2, 5, 1 },
      vim.tbl_map(function(i)
        return i.pr.number
      end, items)
    )
  end)
end)
