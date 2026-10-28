-- Review queue (<leader>rq): the open PRs in the current repo that actually need
-- MY review, as a picker that jumps straight into a review-mode worktree tab.
--
-- "Requested" is not the same as "needed". GitHub's `review-requested:@me`
-- includes every request to every team I'm in (in a monorepo, a broad parent
-- team is on nearly everything), and keeps listing a PR after someone else has
-- already satisfied the CODEOWNERS rule I'd satisfy. Conversely, submitting any
-- review -- even a comment -- removes my request, so a PR I only commented on
-- drops out of that search while still needing my approval. So the candidates
-- are `review-requested:@me` + `reviewed-by:@me`, and classify() decides from
-- the PR's files, CODEOWNERS and the approvals so far.
--
-- Tiers:
--   1 needs you    requested by name (or I commented), and owns files no
--                  other owner has approved; or asked for by name outright
--   2 back to you  I requested changes (blocking) and it has new commits; or
--                  re-requested after an approval that new commits overtook
--   3 your team    a team I'm in owns files nobody's approved, but nobody
--                  asked for me by name
--
-- Per-repo exclusions live in the repo's own git config, not here (this config
-- is public): `git config --add reviewqueue.excludeTeam org/team`. An excluded
-- team only counts when I'm requested by name.
--
-- The same fetch also lists MY open PRs (<leader>rm), the other way round:
-- what's waiting on me to move them along (classify_mine()).
--   1 to fix       checks failing, changes requested, review threads someone
--                  else has the last word in, conflicts, or kicked out of the
--                  merge queue
--   2 to merge     every file a code owner's approved, and it targets the
--                  default branch (a stacked PR waits on the one below it)
--   3 to finish    a draft, or loose ends: unresolved threads I've answered,
--                  or that new commits made outdated
--   4 queued       in the merge queue, or auto-merge is on
--   5 waiting      on reviewers, or on the stack below it
-- "Approved" is worked out from CODEOWNERS rather than taken from GitHub's
-- reviewDecision, which is null under rulesets-only protection.

local M = {}

local diffsize = require("util.diffsize")

-- ---------------------------------------------------------------------------
-- CODEOWNERS

--- Split a CODEOWNERS line into tokens: whitespace-separated, `\` escapes the
--- next character (`\ ` for a space in a path, `\#` for a leading #), and an
--- unescaped `#` at the start of a token begins a comment.
---@param line string
---@return string[]
local function tokens(line)
  local out, cur, i = {}, nil, 1
  while i <= #line do
    local c = line:sub(i, i)
    if c == "\\" and i < #line then
      cur = (cur or "") .. line:sub(i + 1, i + 1)
      i = i + 1
    elseif c:match("%s") then
      if cur then
        out[#out + 1], cur = cur, nil
      end
    elseif c == "#" and not cur then
      break
    else
      cur = (cur or "") .. c
    end
    i = i + 1
  end
  if cur then
    out[#out + 1] = cur
  end
  return out
end

--- One glob path segment as an anchored Lua pattern: `*` is any run of
--- characters and `?` any one character (neither crosses `/`: segments don't
--- contain one).
---@param seg string
---@return string
local function seg_pattern(seg)
  local p = seg:gsub("[%^%$%(%)%%%.%[%]%+%-]", "%%%0"):gsub("%*", ".*"):gsub("%?", ".")
  return "^" .. p .. "$"
end

---@param s string
---@return string[]
local function split(s)
  local out = {}
  for part in s:gmatch("[^/]+") do
    out[#out + 1] = part
  end
  return out
end

--- Does CODEOWNERS `pattern` match repo-relative file `path`? GitHub's rules,
--- which are gitignore's minus negation and character ranges:
---   * a leading or inner `/` anchors to the repo root; otherwise the pattern
---     matches at any depth;
---   * `**` spans any number of directories, `*` stays within one;
---   * a pattern matching a directory owns everything under it -- except that
---     a final `*` (`docs/*`) owns only that directory's direct children;
---   * a trailing `/` matches directories only.
---@param pattern string
---@param path string
---@return boolean
function M.glob_match(pattern, path)
  local dir_only = pattern:sub(-1) == "/"
  pattern = pattern:gsub("/+$", "")
  local anchored = pattern:find("/") ~= nil
  local pat = split(pattern)
  if not anchored then
    table.insert(pat, 1, "**")
  end
  local segs = split(path)
  local n = #segs
  local last_star = pat[#pat] == "*"

  -- The pattern consumed segs[1..k]: the whole path, or a leading directory.
  local function accept(k)
    if k == n then
      return not dir_only
    end
    return k > 0 and (dir_only or not last_star)
  end

  local function match(pi, si)
    if pi > #pat then
      return accept(si - 1)
    end
    if pat[pi] == "**" then
      return match(pi + 1, si) or (si <= n and match(pi, si + 1))
    end
    return si <= n and segs[si]:match(seg_pattern(pat[pi])) ~= nil and match(pi + 1, si + 1)
  end
  return match(1, 1)
end

---@class reviewqueue.Rule
---@field pattern string
---@field owners string[] lowercased, without the leading `@`

--- Parse a CODEOWNERS file into rules, in file order.
---@param text string
---@return reviewqueue.Rule[]
function M.parse_codeowners(text)
  local rules = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local toks = tokens(line)
    if #toks > 0 then
      local owners = {}
      for i = 2, #toks do
        -- Emails are valid owners but can't be tied to a login here; skip.
        if toks[i]:sub(1, 1) == "@" then
          owners[#owners + 1] = toks[i]:sub(2):lower()
        end
      end
      rules[#rules + 1] = { pattern = toks[1], owners = owners }
    end
  end
  return rules
end

--- Owners of `path`: the LAST matching rule wins, and a matching rule with no
--- owners un-owns the path (that's how CODEOWNERS carves out exceptions).
---@param rules reviewqueue.Rule[]
---@param path string
---@return string[]
function M.owners(rules, path)
  for i = #rules, 1, -1 do
    if M.glob_match(rules[i].pattern, path) then
      return rules[i].owners
    end
  end
  return {}
end

-- ---------------------------------------------------------------------------
-- Classification

---@class reviewqueue.Review
---@field author string
---@field state string APPROVED | CHANGES_REQUESTED | DISMISSED
---@field commit string? oid the review was made on

---@class reviewqueue.PR
---@field number integer
---@field title string
---@field url string
---@field author string
---@field draft boolean
---@field head string head ref name
---@field base string base ref name
---@field head_oid string
---@field cross_repo boolean
---@field body string?
---@field user_requests string[] logins requested by name
---@field team_requests string[] "org/team" slugs requested
---@field reviews reviewqueue.Review[] latest opinionated review per user
---@field files string[]
---@field changes { path: string, additions: integer, deletions: integer }[]
---@field size diffsize.Size? set by fetch() for the PRs that make the list
---@field reviewed_by_me boolean? found via `reviewed-by:@me`
--- The rest only for my own PRs (MINE_FIELDS):
---@field checks string? statusCheckRollup state: SUCCESS | FAILURE | ERROR | PENDING | EXPECTED
---@field failing string[] names of the failing checks
---@field threads { resolved: boolean, outdated: boolean, last: string? }[] review threads, with who spoke last
---@field mergeable string? MERGEABLE | CONFLICTING | UNKNOWN (computed lazily by GitHub)
---@field merge_state string? mergeStateStatus; only BEHIND is used
---@field auto_merge boolean
---@field queue { state: string, position: integer? }? merge queue entry
---@field dequeued { reason: string, by: string? }? last merge-queue event was a removal

---@class reviewqueue.Ctx
---@field me string
---@field my_teams table<string, true> lowercased slugs, ancestors included
---@field exclude table<string, true> lowercased slugs
---@field rules reviewqueue.Rule[]
---@field teams_of table<string, table<string, true>> login -> its team slugs

---@class reviewqueue.Verdict
---@field tier integer 1-3 for review, 1-5 for mine
---@field reason string
---@field notes string[]? extra preview lines
---@field review boolean? mine: open it in review mode (there are threads to answer or resolve)

local lower = string.lower

---@param set table<string, true>
---@return string[]
local function sorted_keys(set)
  local out = vim.tbl_keys(set)
  table.sort(out)
  return out
end

--- Does `login` satisfy CODEOWNERS `owner` ("user" or "org/team")?
---@param ctx reviewqueue.Ctx
---@param login string lowercased
---@param owner string lowercased
local function satisfies(ctx, login, owner)
  if owner == login then
    return true
  end
  local teams = ctx.teams_of[login]
  return teams ~= nil and teams[owner] == true
end

--- Does this PR need my review, and how badly? nil = no.
---@param pr reviewqueue.PR
---@param ctx reviewqueue.Ctx
---@return reviewqueue.Verdict?
function M.classify(pr, ctx)
  local me = lower(ctx.me)
  if lower(pr.author) == me or pr.draft then
    return nil
  end

  local by_name = false
  for _, login in ipairs(pr.user_requests) do
    by_name = by_name or lower(login) == me
  end

  local mine ---@type reviewqueue.Review?
  local approvers = {} ---@type string[]
  for _, r in ipairs(pr.reviews) do
    local who = lower(r.author)
    if who == me then
      mine = r
    elseif r.state == "APPROVED" then
      approvers[#approvers + 1] = who
    end
  end
  -- A dismissed review no longer counts for anything, mine included.
  if mine and mine.state == "DISMISSED" then
    mine = nil
  end

  if mine then
    if mine.commit == pr.head_oid then
      return nil -- already reviewed what's there now
    end
    if mine.state == "CHANGES_REQUESTED" then
      -- Blocks the merge until I look again, whatever anyone else says.
      return { tier = 2, reason = "new commits since you requested changes" }
    end
    -- A stale approval still counts unless the branch dismisses stale reviews
    -- (in which case it arrives as DISMISSED, above), so new commits alone
    -- don't need me. Being asked again does.
    if by_name then
      return { tier = 2, reason = "re-requested since your approval" }
    end
    return nil
  end

  -- My request disappears once I submit a comment-only review, but a comment
  -- isn't a review decision: treat it as still asked.
  local asked = by_name or pr.reviewed_by_me == true

  -- The files I could approve for, and which of my routes (me, or a team of
  -- mine) still has unapproved files: any one owner's approval covers a file.
  local owned, routes = 0, {} ---@type integer, table<string, true>
  for _, path in ipairs(pr.files) do
    local owners = M.owners(ctx.rules, path)
    local my_routes = {}
    for _, o in ipairs(owners) do
      if o == me or ctx.my_teams[o] then
        my_routes[#my_routes + 1] = o
      end
    end
    if #my_routes > 0 then
      owned = owned + 1
      local covered = false
      for _, a in ipairs(approvers) do
        for _, o in ipairs(owners) do
          covered = covered or satisfies(ctx, a, o)
        end
      end
      if not covered then
        for _, o in ipairs(my_routes) do
          routes[o] = true
        end
      end
    end
  end

  local real = {} ---@type table<string, true>
  for o in pairs(routes) do
    if not ctx.exclude[o] then
      real[o] = true
    end
  end

  if next(routes) then
    local via = next(real) and real or routes
    local reason = "owns unapproved files via " .. table.concat(sorted_keys(via), ", ")
    if asked then
      return { tier = 1, reason = reason }
    end
    if next(real) then
      return { tier = 3, reason = reason }
    end
    return nil -- only via an excluded team, and nobody named me
  end
  if owned == 0 and by_name then
    -- Not a code owner of anything here: a person picked me deliberately.
    return { tier = 1, reason = "requested by name" }
  end
  return nil -- every file I could approve already has an owner's approval
end

--- The CODEOWNERS owners whose approval `pr` still lacks: every owner of each
--- file that none of `approvers` can approve for. Empty = fully approved
--- (including when nothing in it is owned).
---@param pr reviewqueue.PR
---@param ctx reviewqueue.Ctx
---@param approvers string[] lowercased logins
---@return string[]
function M.awaiting_owners(pr, ctx, approvers)
  local waiting = {} ---@type table<string, true>
  for _, path in ipairs(pr.files) do
    local owners = M.owners(ctx.rules, path)
    local covered = false
    for _, a in ipairs(approvers) do
      for _, o in ipairs(owners) do
        covered = covered or satisfies(ctx, a, o)
      end
    end
    if not covered then
      for _, o in ipairs(owners) do
        waiting[o] = true
      end
    end
  end
  return sorted_keys(waiting)
end

---@class reviewqueue.MineCtx: reviewqueue.Ctx
---@field default_branch string?
---@field heads table<string, integer> head ref -> number, over my open PRs

local CHECKS_FAILED = { FAILURE = true, ERROR = true }
local CHECKS_PENDING = { PENDING = true, EXPECTED = true }

--- What's holding up one of my own PRs. Unlike classify(), never nil: every
--- open PR of mine is listed somewhere.
---@param pr reviewqueue.PR
---@param ctx reviewqueue.MineCtx
---@return reviewqueue.Verdict
function M.classify_mine(pr, ctx)
  local me = lower(ctx.me)
  local approvers, blockers = {}, {} ---@type string[], string[]
  for _, r in ipairs(pr.reviews) do
    local who = lower(r.author)
    if who ~= me then
      if r.state == "APPROVED" then
        approvers[#approvers + 1] = who
      elseif r.state == "CHANGES_REQUESTED" then
        blockers[#blockers + 1] = "@" .. r.author
      end
    end
  end

  -- Unresolved threads: someone else's last word is a question for me (to
  -- fix). One I've answered, or one new commits have made outdated, is a loose
  -- end -- probably dealt with, but still open until somebody resolves it.
  local unanswered, loose, outdated = 0, 0, 0
  for _, t in ipairs(pr.threads) do
    if not t.resolved then
      if t.outdated then
        loose, outdated = loose + 1, outdated + 1
      elseif t.last and lower(t.last) ~= me then
        unanswered = unanswered + 1
      else
        loose = loose + 1
      end
    end
  end

  local fix = {} ---@type string[]
  local notes = {} ---@type string[]
  if CHECKS_FAILED[pr.checks or ""] then
    fix[#fix + 1] = "checks failing"
    if #pr.failing > 0 then
      notes[#notes + 1] = "failing: " .. table.concat(pr.failing, ", ")
    end
  end
  if #blockers > 0 then
    fix[#fix + 1] = "changes requested by " .. table.concat(blockers, ", ")
  end
  if unanswered > 0 then
    fix[#fix + 1] = ("%d unanswered thread%s"):format(unanswered, unanswered == 1 and "" or "s")
  end
  if pr.mergeable == "CONFLICTING" then
    fix[#fix + 1] = "merge conflicts"
  end
  if pr.queue and pr.queue.state == "UNMERGEABLE" then
    fix[#fix + 1] = "unmergeable in the merge queue"
  elseif not pr.queue and pr.dequeued and lower(pr.dequeued.by or "") ~= me then
    -- Taking it out myself was deliberate; GitHub taking it out wasn't.
    local why = pr.dequeued.reason ~= "" and (": " .. pr.dequeued.reason:lower()) or ""
    fix[#fix + 1] = "removed from the merge queue" .. why
  end
  local finish = {} ---@type string[]
  if pr.draft then
    finish[#finish + 1] = "draft"
  end
  if loose > 0 then
    finish[#finish + 1] = ("%d thread%s to resolve%s"):format(
      loose,
      loose == 1 and "" or "s",
      outdated > 0 and (" (%d outdated)"):format(outdated) or ""
    )
  end
  -- Review mode is where threads are answered and resolved (nitpick).
  local review = #blockers > 0 or unanswered > 0 or loose > 0

  local function verdict(tier, reasons)
    return { tier = tier, reason = table.concat(reasons, ", "), notes = notes, review = review }
  end

  -- A draft is unfinished whatever else is wrong with it: that's said too,
  -- but it's not a fix to a PR that's meant to be done.
  if pr.draft then
    return verdict(3, vim.list_extend(finish, fix))
  end
  if #fix > 0 then
    return verdict(1, vim.list_extend(fix, finish))
  end
  -- Queued (or auto-merging) lands without me: loose ends don't hold it up.
  if pr.queue then
    local state = pr.queue.state:lower():gsub("_", " ")
    local at = pr.queue.position and ("#%d in the merge queue"):format(pr.queue.position)
      or "in the merge queue"
    return verdict(4, { at, state })
  end
  if pr.auto_merge then
    return verdict(4, { "auto-merge on" })
  end
  if #finish > 0 then
    return verdict(3, finish)
  end

  local awaiting = M.awaiting_owners(pr, ctx, approvers)
  local approved = #approvers > 0 and #awaiting == 0
  local status = approved and "approved"
    or #approvers > 0 and ("approved, awaiting " .. table.concat(awaiting, ", "))
    or #awaiting > 0 and ("awaiting " .. table.concat(awaiting, ", "))
    or "awaiting review"

  -- GitHub retargets a stacked PR when the one below merges; until then,
  -- merging it would land it in that branch, not the default one.
  if ctx.default_branch and pr.base ~= ctx.default_branch then
    local below = ctx.heads[pr.base]
    return verdict(5, { status, "stacked on " .. (below and ("#" .. below) or pr.base) })
  end
  if not approved then
    return verdict(5, { status })
  end
  local extra = {}
  if CHECKS_PENDING[pr.checks or ""] then
    extra[#extra + 1] = "checks pending"
  end
  if pr.merge_state == "BEHIND" then
    extra[#extra + 1] = "behind " .. pr.base
  end
  return verdict(2, vim.list_extend({ status }, extra))
end

--- Verdicts in display order: tier, then newest PR first.
---@param items { pr: reviewqueue.PR, verdict: reviewqueue.Verdict }[]
function M.sort(items)
  table.sort(items, function(a, b)
    if a.verdict.tier ~= b.verdict.tier then
      return a.verdict.tier < b.verdict.tier
    end
    return a.pr.number > b.pr.number
  end)
  return items
end

--- Normalize a search-result PR node from the GraphQL query below.
---@param node table
---@param reviewed_by_me boolean
---@return reviewqueue.PR
function M.from_node(node, reviewed_by_me)
  local function nodes(conn)
    return type(conn) == "table" and type(conn.nodes) == "table" and conn.nodes or {}
  end
  local function str(v)
    return type(v) == "string" and v or nil
  end
  local pr = {
    number = node.number,
    title = str(node.title) or "",
    url = str(node.url) or "",
    author = type(node.author) == "table" and str(node.author.login) or "ghost",
    draft = node.isDraft == true,
    head = str(node.headRefName) or "",
    base = str(node.baseRefName) or "",
    head_oid = str(node.headRefOid) or "",
    cross_repo = node.isCrossRepository == true,
    body = str(node.body),
    user_requests = {},
    team_requests = {},
    reviews = {},
    files = {},
    changes = {},
    reviewed_by_me = reviewed_by_me,
    failing = {},
    threads = {},
    mergeable = str(node.mergeable),
    merge_state = str(node.mergeStateStatus),
    auto_merge = type(node.autoMergeRequest) == "table",
  }
  if type(node.mergeQueueEntry) == "table" then
    pr.queue = {
      state = str(node.mergeQueueEntry.state) or "",
      position = tonumber(node.mergeQueueEntry.position),
    }
  end
  -- timelineItems is filtered to the queue's added/removed events, last one.
  local ev = nodes(node.timelineItems)[1]
  if ev and ev.__typename == "RemovedFromMergeQueueEvent" then
    pr.dequeued = {
      reason = str(ev.reason) or "",
      by = type(ev.actor) == "table" and str(ev.actor.login) or nil,
    }
  end
  for _, t in ipairs(nodes(node.reviewThreads)) do
    local last = nodes(t.comments)[1]
    table.insert(pr.threads, {
      resolved = t.isResolved == true,
      outdated = t.isOutdated == true,
      last = last and type(last.author) == "table" and str(last.author.login) or nil,
    })
  end
  local head = nodes(node.commits)[1]
  local rollup = head and type(head.commit) == "table" and head.commit.statusCheckRollup
  if type(rollup) == "table" then
    pr.checks = str(rollup.state)
    -- CheckRuns carry a conclusion, legacy StatusContexts a state. A name
    -- can repeat (one job in several workflows): list it once.
    local seen = {}
    for _, c in ipairs(nodes(rollup.contexts)) do
      local result = c.conclusion or c.state
      if
        result == "FAILURE"
        or result == "ERROR"
        or result == "TIMED_OUT"
        or result == "CANCELLED"
        or result == "ACTION_REQUIRED"
        or result == "STARTUP_FAILURE"
      then
        local name = str(c.name) or str(c.context) or "?"
        if not seen[name] then
          seen[name] = true
          table.insert(pr.failing, name)
        end
      end
    end
  end
  for _, rr in ipairs(nodes(node.reviewRequests)) do
    local who = type(rr.requestedReviewer) == "table" and rr.requestedReviewer or {}
    if str(who.login) then
      table.insert(pr.user_requests, who.login)
    elseif str(who.combinedSlug) then
      table.insert(pr.team_requests, who.combinedSlug)
    end
  end
  for _, r in ipairs(nodes(node.latestOpinionatedReviews)) do
    if type(r.author) == "table" and str(r.author.login) then
      table.insert(pr.reviews, {
        author = r.author.login,
        state = r.state,
        commit = type(r.commit) == "table" and str(r.commit.oid) or nil,
      })
    end
  end
  for _, f in ipairs(nodes(node.files)) do
    table.insert(pr.files, f.path)
    table.insert(pr.changes, {
      path = f.path,
      additions = tonumber(f.additions) or 0,
      deletions = tonumber(f.deletions) or 0,
    })
  end
  return pr
end

--- Lowercased team slugs from an `organization.teams` connection, each team's
--- ancestors included: a child team's members can approve for the parent.
---@param conn table?
---@return table<string, true>
function M.team_set(conn)
  local set = {}
  for _, t in ipairs(type(conn) == "table" and conn.nodes or {}) do
    set[lower(t.combinedSlug)] = true
    for _, a in ipairs(type(t.ancestors) == "table" and t.ancestors.nodes or {}) do
      set[lower(a.combinedSlug)] = true
    end
  end
  return set
end

-- ---------------------------------------------------------------------------
-- GitHub (async; everything below runs inside a coroutine)

--- Run a command without blocking the editor; resume with its result.
---@param cmd string[]
---@param opts table vim.system opts
---@return vim.SystemCompleted
local function run(cmd, opts)
  local co = assert(coroutine.running(), "reviewqueue: not in a coroutine")
  vim.system(cmd, vim.tbl_extend("force", { text = true }, opts), function(res)
    vim.schedule(function()
      local ok, err = coroutine.resume(co, res)
      if not ok then
        vim.notify("review queue: " .. tostring(err), vim.log.levels.ERROR)
      end
    end)
  end)
  return coroutine.yield()
end

--- A GraphQL request through gh (its auth, its host). Errors are raised.
---@param query string
---@param variables table?
---@return table data
local function graphql(query, variables)
  local body = vim.json.encode({ query = query, variables = variables or vim.empty_dict() })
  local res = run({ "gh", "api", "graphql", "--input", "-" }, { stdin = body })
  local ok, decoded =
    pcall(vim.json.decode, res.stdout or "", { luanil = { object = true, array = true } })
  if res.code ~= 0 or not ok or type(decoded) ~= "table" or not decoded.data then
    local msg = ok
      and type(decoded) == "table"
      and decoded.errors
      and decoded.errors[1]
      and decoded.errors[1].message
    error(
      msg or vim.trim(res.stderr or "") ~= "" and vim.trim(res.stderr) or "gh api graphql failed",
      0
    )
  end
  return decoded.data
end

local PR_FIELDS = [[
  number title url isDraft body headRefName baseRefName headRefOid isCrossRepository
  author { login }
  reviewRequests(first: 50) {
    nodes { requestedReviewer { ... on User { login } ... on Team { combinedSlug } } }
  }
  latestOpinionatedReviews(first: 100) { nodes { state author { login } commit { oid } } }
  files(first: 100) { pageInfo { hasNextPage endCursor } nodes { path additions deletions } }
]]

-- My own PRs also need what's holding them up. The rollup state is what
-- classifies; the contexts only name the failing checks in the preview, so
-- details() pages past the first 100 only when the rollup has failed.
local MINE_FIELDS = [[
  mergeable mergeStateStatus
  autoMergeRequest { enabledAt }
  mergeQueueEntry { state position }
  timelineItems(last: 1, itemTypes: [ADDED_TO_MERGE_QUEUE_EVENT, REMOVED_FROM_MERGE_QUEUE_EVENT]) {
    nodes { __typename ... on RemovedFromMergeQueueEvent { reason actor { login } } }
  }
  reviewThreads(first: 100) { nodes { isResolved isOutdated comments(last: 1) { nodes { author { login } } } } }
  commits(last: 1) { nodes { commit { statusCheckRollup { state contexts(first: 100) { %s } } } } }
]]
local CONTEXTS = [[
  pageInfo { hasNextPage endCursor }
  nodes { ... on CheckRun { name conclusion } ... on StatusContext { context state } }
]]
MINE_FIELDS = MINE_FIELDS:format(CONTEXTS)

-- Numbers only: the per-PR fields (files above all) make a search page slow,
-- and search pages can only be walked one after another. Details are then
-- fetched by number in parallel batches (details()).
local SEARCH = [[
query($q: String!, $after: String) {
  search(query: $q, type: ISSUE, first: 100, after: $after) {
    pageInfo { hasNextPage endCursor }
    nodes { ... on PullRequest { number } }
  }
}]]

local MORE_FILES = [[
query($owner: String!, $name: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      files(first: 100, after: $after) { pageInfo { hasNextPage endCursor } nodes { path additions deletions } }
    }
  }
}]]

local MORE_CONTEXTS = ([[
query($owner: String!, $name: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      commits(last: 1) { nodes { commit { statusCheckRollup {
        contexts(first: 100, after: $after) { %s }
      } } } }
    }
  }
}]]):format(CONTEXTS)

local TEAMS =
  "teams(first: 100, userLogins: [%s]) { nodes { combinedSlug ancestors(first: 20) { nodes { combinedSlug } } } }"

--- Run thunks concurrently (each in its own coroutine), wait for all of them,
--- and return their results in order. The first error is re-raised.
---@param fns (fun(): any)[]
---@return any[]
local function parallel(fns)
  local co = assert(coroutine.running(), "reviewqueue: not in a coroutine")
  local results, pending, failed = {}, #fns, nil
  if pending == 0 then
    return results
  end
  for i, fn in ipairs(fns) do
    coroutine.wrap(function()
      local ok, res = pcall(fn)
      if ok then
        results[i] = res
      else
        failed = failed or res
      end
      pending = pending - 1
      if pending == 0 then
        -- Scheduled, not direct: a thunk that never yielded finishes before
        -- this coroutine has yielded below, and can't resume it yet.
        vim.schedule(function()
          local rok, err = coroutine.resume(co)
          if not rok then
            vim.notify("review queue: " .. tostring(err), vim.log.levels.ERROR)
          end
        end)
      end
    end)()
  end
  coroutine.yield()
  if failed then
    error(failed, 0)
  end
  return results
end

--- Numbers of the open PRs matching a search qualifier.
---@param repo { owner: string, name: string }
---@param qualifier string
---@return integer[]
local function search(repo, qualifier)
  local q = ("repo:%s/%s is:pr is:open %s"):format(repo.owner, repo.name, qualifier)
  local out, after = {}, nil
  repeat
    local page = graphql(SEARCH, { q = q, after = after }).search
    for _, node in ipairs(page.nodes) do
      if node.number then
        out[#out + 1] = node.number
      end
    end
    after = page.pageInfo.endCursor
  until not page.pageInfo.hasNextPage
  return out
end

--- Full PR nodes for some numbers, in one request, files fully paginated.
---@param repo { owner: string, name: string }
---@param numbers integer[]
---@param extra? string more fields (MINE_FIELDS)
---@return table[] nodes
local function details(repo, numbers, extra)
  local fields = {}
  for i, n in ipairs(numbers) do
    fields[i] = ("p%d: pullRequest(number: %d) { %s %s }"):format(i, n, PR_FIELDS, extra or "")
  end
  local query = ("query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { %s } }"):format(
    table.concat(fields, "\n")
  )
  local data = graphql(query, { owner = repo.owner, name = repo.name }).repository
  local out = {}
  for i = 1, #numbers do
    local node = data["p" .. i]
    if node then
      local files = node.files
      while files.pageInfo.hasNextPage do
        local more = graphql(MORE_FILES, {
          owner = repo.owner,
          name = repo.name,
          number = node.number,
          after = files.pageInfo.endCursor,
        }).repository.pullRequest.files
        vim.list_extend(files.nodes, more.nodes)
        files.pageInfo = more.pageInfo
      end
      local head = node.commits and node.commits.nodes and node.commits.nodes[1]
      local rollup = head and head.commit and head.commit.statusCheckRollup
      local contexts = rollup
        and (rollup.state == "FAILURE" or rollup.state == "ERROR")
        and rollup.contexts
      while contexts and contexts.pageInfo.hasNextPage do
        local more = graphql(MORE_CONTEXTS, {
          owner = repo.owner,
          name = repo.name,
          number = node.number,
          after = contexts.pageInfo.endCursor,
        }).repository.pullRequest.commits.nodes[1].commit.statusCheckRollup.contexts
        vim.list_extend(contexts.nodes, more.nodes)
        contexts.pageInfo = more.pageInfo
      end
      out[#out + 1] = node
    end
  end
  return out
end

--- CODEOWNERS text per base branch, from GitHub (not the local checkout, which
--- may be stale or on another branch). First of .github/, root, docs/ wins.
---@param repo { owner: string, name: string }
---@param bases string[]
---@return table<string, string>
local function codeowners(repo, bases)
  local locations = { ".github/CODEOWNERS", "CODEOWNERS", "docs/CODEOWNERS" }
  local fields, vars, decls = {}, { owner = repo.owner, name = repo.name }, {}
  for bi, base in ipairs(bases) do
    for li, loc in ipairs(locations) do
      local key = ("c%d_%d"):format(bi, li)
      vars[key] = base .. ":" .. loc
      decls[#decls + 1] = ("$%s: String!"):format(key)
      fields[#fields + 1] = ("%s: object(expression: $%s) { ... on Blob { text } }"):format(
        key,
        key
      )
    end
  end
  local query = ("query($owner: String!, $name: String!, %s) { repository(owner: $owner, name: $name) { %s } }"):format(
    table.concat(decls, ", "),
    table.concat(fields, "\n")
  )
  local data = graphql(query, vars).repository
  local out = {}
  for bi, base in ipairs(bases) do
    for li = 1, #locations do
      local blob = data[("c%d_%d"):format(bi, li)]
      if not out[base] and blob and blob.text then
        out[base] = blob.text
      end
    end
  end
  return out
end

--- Team memberships (ancestors included) for each login, in one request.
---@param org string
---@param logins string[]
---@return table<string, table<string, true>> lowercased login -> slugs
local function teams_of(org, logins)
  if #logins == 0 then
    return {}
  end
  local fields, vars, decls = {}, { org = org }, { "$org: String!" }
  for i, login in ipairs(logins) do
    vars["l" .. i] = login
    decls[#decls + 1] = ("$l%d: String!"):format(i)
    fields[#fields + 1] = ("u%d: organization(login: $org) { %s }"):format(
      i,
      TEAMS:format("$l" .. i)
    )
  end
  local query = ("query(%s) { %s }"):format(table.concat(decls, ", "), table.concat(fields, "\n"))
  -- A user-owned repo has no organization (and no teams): not an error here.
  local ok, data = pcall(graphql, query, vars)
  local out = {}
  for i, login in ipairs(logins) do
    out[lower(login)] = ok and data["u" .. i] and M.team_set(data["u" .. i].teams) or {}
  end
  return out
end

--- Excluded teams from the repo's git config (reviewqueue.excludeTeam).
---@param dir string
---@return table<string, true>
local function excluded(dir)
  local res = run({ "git", "config", "--get-all", "reviewqueue.excludeTeam" }, { cwd = dir })
  local set = {}
  for line in (res.stdout or ""):gmatch("[^\n]+") do
    set[lower(vim.trim(line):gsub("^@", ""))] = true
  end
  return set
end

--- linguist-generated for `paths`, as the base branch's .gitattributes say
--- (the local remote-tracking ref: attributes rarely move, so a stale fetch is
--- fine). Falls back to the checkout's own attributes when that ref isn't
--- here, and to none (lockfiles only, see util/diffsize) outside a git repo.
---@param dir string
---@param base string
---@param paths string[]
---@return table<string, string>
local function attributes(dir, base, paths)
  local opts = { cwd = dir, stdin = diffsize.attr_input(paths) }
  local res = run(diffsize.attr_cmd("refs/remotes/origin/" .. base), opts)
  if res.code ~= 0 then
    res = run(diffsize.attr_cmd(), opts)
  end
  return res.code == 0 and diffsize.parse_attrs(res.stdout or "") or {}
end

--- Set pr.size on each PR, one check-attr per base branch.
---@param dir string
---@param prs reviewqueue.PR[]
local function sizes(dir, prs)
  local by_base = {} ---@type table<string, reviewqueue.PR[]>
  for _, pr in ipairs(prs) do
    by_base[pr.base] = by_base[pr.base] or {}
    table.insert(by_base[pr.base], pr)
  end
  local bases = sorted_keys(by_base)
  local attrs = parallel(vim.tbl_map(function(base)
    return function()
      local paths = {}
      for _, pr in ipairs(by_base[base]) do
        vim.list_extend(paths, pr.files)
      end
      return attributes(dir, base, paths)
    end
  end, bases))
  for i, base in ipairs(bases) do
    for _, pr in ipairs(by_base[base]) do
      pr.size = diffsize.summarize(pr.changes, attrs[i])
    end
  end
end

---@param dir string
---@return { owner: string, name: string }
local function repo_of(dir)
  local view = run({ "gh", "repo", "view", "--json", "owner,name" }, { cwd = dir })
  local ok, info = pcall(vim.json.decode, view.stdout or "")
  if view.code ~= 0 or not ok then
    error("not a GitHub repo: " .. vim.trim(view.stderr or ""), 0)
  end
  return { owner = info.owner.login, name = info.name }
end

--- The diff size of one PR (the greeter's PR under review), or nil if it
--- couldn't be had. Its own fetch rather than `gh pr view --json files`,
--- which stops at 100 files without saying so.
---@param dir string
---@param number integer
---@param cb fun(size: diffsize.Size?)
function M.size(dir, number, cb)
  coroutine.wrap(function()
    local ok, size = pcall(function()
      local node = details(repo_of(dir), { number })[1]
      if not node then
        return nil
      end
      local pr = M.from_node(node, false)
      sizes(dir, { pr })
      return pr.size
    end)
    cb(ok and size or nil)
  end)()
end

---@alias reviewqueue.Item { pr: reviewqueue.PR, verdict: reviewqueue.Verdict }

--- Full PR nodes for `numbers`, fetched in parallel batches of 10.
---@param repo { owner: string, name: string }
---@param numbers integer[]
---@param extra? string
---@return table[]
local function all_details(repo, numbers, extra)
  local batches = {}
  for i = 1, #numbers, 10 do
    local batch = vim.list_slice(numbers, i, i + 9)
    batches[#batches + 1] = function()
      return details(repo, batch, extra)
    end
  end
  local out = {}
  for _, nodes in ipairs(parallel(batches)) do
    vim.list_extend(out, nodes)
  end
  return out
end

--- Both pickers' lists for the repo at `dir`, classified and sorted: the PRs
--- needing my review, and my own open PRs.
---@param dir string
---@return reviewqueue.Item[] items, { owner: string, name: string } repo, reviewqueue.Item[] mine
function M.fetch(dir)
  local repo = repo_of(dir)

  -- Drafts and my own PRs never need my review; filtering in the search also
  -- spares paging a big draft's file list.
  local review_q = "draft:false -author:@me "
  local first = parallel({
    function()
      return graphql("{ viewer { login } }").viewer.login
    end,
    function()
      return search(repo, review_q .. "reviewed-by:@me")
    end,
    function()
      return search(repo, review_q .. "review-requested:@me")
    end,
    function()
      return excluded(dir)
    end,
    function()
      return search(repo, "author:@me")
    end,
    function()
      local q =
        "query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { defaultBranchRef { name } } }"
      local ref = graphql(q, repo).repository.defaultBranchRef
      return ref and ref.name or false
    end,
  })
  local me, reviewed, requested, exclude = first[1], first[2], first[3], first[4]
  local authored, default_branch = first[5], first[6] or nil

  local reviewed_set, numbers = {}, {}
  for _, n in ipairs(reviewed) do
    reviewed_set[n] = true
    numbers[#numbers + 1] = n
  end
  for _, n in ipairs(requested) do
    if not reviewed_set[n] then
      numbers[#numbers + 1] = n
    end
  end

  local fetched = parallel({
    function()
      return all_details(repo, numbers)
    end,
    function()
      return all_details(repo, authored, MINE_FIELDS)
    end,
  })
  local prs, my_prs = {}, {}
  for _, node in ipairs(fetched[1]) do
    prs[#prs + 1] = M.from_node(node, reviewed_set[node.number] == true)
  end
  for _, node in ipairs(fetched[2]) do
    my_prs[#my_prs + 1] = M.from_node(node, false)
  end

  local bases, approvers = {}, { [me] = true }
  for _, list in ipairs({ prs, my_prs }) do
    for _, pr in ipairs(list) do
      bases[pr.base] = true
      for _, r in ipairs(pr.reviews) do
        if r.state == "APPROVED" then
          approvers[r.author] = true
        end
      end
    end
  end
  local second = parallel({
    function()
      return next(bases) and codeowners(repo, sorted_keys(bases)) or {}
    end,
    function()
      return teams_of(repo.owner, sorted_keys(approvers))
    end,
  })
  local owners_text, teams = second[1], second[2]

  local rules = {}
  local function rules_for(base)
    rules[base] = rules[base] or M.parse_codeowners(owners_text[base] or "")
    return rules[base]
  end
  local items = {}
  for _, pr in ipairs(prs) do
    local verdict = M.classify(pr, {
      me = me,
      my_teams = teams[lower(me)] or {},
      exclude = exclude,
      rules = rules_for(pr.base),
      teams_of = teams,
    })
    if verdict then
      items[#items + 1] = { pr = pr, verdict = verdict }
    end
  end

  local heads = {}
  for _, pr in ipairs(my_prs) do
    heads[pr.head] = pr.number
  end
  local mine = {}
  for _, pr in ipairs(my_prs) do
    mine[#mine + 1] = {
      pr = pr,
      verdict = M.classify_mine(pr, {
        me = me,
        my_teams = teams[lower(me)] or {},
        exclude = exclude,
        rules = rules_for(pr.base),
        teams_of = teams,
        default_branch = default_branch,
        heads = heads,
      }),
    }
  end

  local listed = {}
  for _, list in ipairs({ items, mine }) do
    for _, it in ipairs(list) do
      listed[#listed + 1] = it.pr
    end
  end
  sizes(dir, listed)
  return M.sort(items), repo, M.sort(mine)
end

-- ---------------------------------------------------------------------------
-- Opening a PR for review

--- Fetch the PR head so the worktree starts at what's actually on the PR (a
--- tier-2 PR is there BECAUSE it moved), open it as a workspace tab, and turn
--- review mode on there against the PR's own base.
---
--- `review = false` (my own PRs, nothing to answer) just opens the tab: no
--- review mode, and no "behind the PR head" warning -- my checkout being
--- ahead of what's pushed is normal.
---@param pr reviewqueue.PR
---@param dir string a directory inside the repo
---@param opts? { review: boolean? } review defaults to true
function M.open(pr, dir, opts)
  local review = not (opts and opts.review == false)
  local vcs = require("util.vcs")
  if pr.cross_repo then
    -- The head lives in a fork: origin has no branch by that name, and
    -- worktree.open would quietly branch a new one off HEAD instead.
    vim.notify(
      "#" .. pr.number .. " is from a fork; not supported yet",
      vim.log.levels.WARN,
      { title = "review queue" }
    )
    return
  end
  local jj = vcs.is_jj(dir)

  local function on_open(path)
    if not review then
      return
    end
    local triage = require("triage")
    if not triage.is_enabled() then
      triage.toggle()
    end
    -- triage auto-detects the default branch; a stacked PR targets another.
    local base = jj and (pr.base .. "@origin") or ("origin/" .. pr.base)
    triage.set_target(base)
    -- An existing worktree keeps its own checkout: say so if it's behind.
    local head = jj and { "jj", "log", "--no-graph", "-r", "@-", "-T", "commit_id" }
      or { "git", "rev-parse", "HEAD" }
    vim.system(head, { cwd = path, text = true }, function(res)
      local at = vim.trim(res.stdout or "")
      if res.code == 0 and at ~= pr.head_oid and not (jj and at == "") then
        vim.schedule(function()
          vim.notify(
            ("worktree is at %s, PR head is %s: pull to review the latest"):format(
              at:sub(1, 8),
              pr.head_oid:sub(1, 8)
            ),
            vim.log.levels.WARN,
            { title = "review queue" }
          )
        end)
      end
    end)
  end

  local function fetched(_, err)
    if err then
      vim.notify(
        "fetch " .. pr.head .. ": " .. err,
        vim.log.levels.ERROR,
        { title = "review queue" }
      )
      return
    end
    vcs.open_tab(pr.head, dir, on_open)
  end
  if jj then
    vim.system(
      { "jj", "git", "fetch", "--remote", "origin", "--branch", pr.head },
      { cwd = dir, text = true },
      function(res)
        vim.schedule(function()
          fetched(nil, res.code ~= 0 and vim.trim(res.stderr or "") or nil)
        end)
      end
    )
  else
    -- git_async: a progress float, since a fetch in a big repo takes a while.
    require("util.worktree").git_async(
      dir,
      { "fetch", "origin", pr.head },
      "fetching " .. pr.head,
      fetched
    )
  end
end

-- ---------------------------------------------------------------------------
-- Picker

local TIERS = {
  { label = "needs you", hl = "DiagnosticError" },
  { label = "back to you", hl = "DiagnosticWarn" },
  { label = "your team", hl = "Comment" },
}
local MINE_TIERS = {
  { label = "to fix", hl = "DiagnosticError" },
  { label = "to merge", hl = "Added" },
  { label = "to finish", hl = "DiagnosticWarn" },
  { label = "queued", hl = "Special" },
  { label = "waiting", hl = "Comment" },
}

-- ---------------------------------------------------------------------------
-- Cache: the queue is refreshed in the background (setup()), so the picker
-- opens at once and the greeter can show counts without a fetch of its own.

---@class reviewqueue.Entry
---@field items reviewqueue.Item[]? PRs needing my review
---@field mine reviewqueue.Item[]? my own open PRs
---@field repo { owner: string, name: string }?
---@field err string? the last fetch failed (not a GitHub repo, gh logged out)
---@field at integer vim.uv.now() of the fetch

--- Repo key -> last fetch. Keyed by the MAIN worktree / workspace root, so all
--- of a repo's worktree tabs share one queue.
---@type table<string, reviewqueue.Entry>
M.cache = {}
local inflight = {} ---@type table<string, fun(entry: reviewqueue.Entry)[]>
local keys = {} ---@type table<string, string|false>

M.INTERVAL_MS = 5 * 60 * 1000
-- An opened picker shows the cache as is, and refreshes behind it past this.
local STALE_MS = 60 * 1000

--- The cache key for the repo containing `dir`, or nil outside a repo.
--- Memoised: the greeter asks on every render, and git rev-parse is a process.
---@param dir string
---@return string?
function M.key(dir)
  if keys[dir] == nil then
    local root
    if require("util.vcs").is_jj(dir) then
      root = require("util.jjworkspace").root(dir)
    else
      root = require("util.worktree").root(dir)
    end
    keys[dir] = root or false
  end
  return keys[dir] or nil
end

--- Refetch the queue for `dir`'s repo in the background. Concurrent calls
--- share one fetch; `cb` (optional) gets the fresh entry.
---@param dir string
---@param cb? fun(entry: reviewqueue.Entry)
function M.refresh(dir, cb)
  local key = M.key(dir)
  if not key then
    return
  end
  if inflight[key] then
    table.insert(inflight[key], cb)
    return
  end
  inflight[key] = { cb }
  coroutine.wrap(function()
    local ok, items, repo, mine = pcall(M.fetch, key)
    local entry = ok and { items = items, mine = mine, repo = repo, at = vim.uv.now() }
      or { err = tostring(items), at = vim.uv.now() }
    -- A failed refresh keeps the last good list: a blip in the background
    -- shouldn't blank the greeter's count.
    local prev = M.cache[key]
    if not ok and prev and prev.items then
      entry = vim.tbl_extend("force", prev, { err = entry.err, at = entry.at })
    end
    M.cache[key] = entry
    local cbs = inflight[key]
    inflight[key] = nil
    for _, f in pairs(cbs) do
      f(entry)
    end
    if
      not vim.deep_equal(M.counts_of(prev), M.counts_of(entry))
      or not vim.deep_equal(M.counts_of(prev, "mine"), M.counts_of(entry, "mine"))
    then
      pcall(function()
        require("config.greeter").update_dashboards()
      end)
    end
  end)()
end

--- Items per tier, or nil when there's no list.
---@param entry reviewqueue.Entry?
---@param list? "items"|"mine" default "items"
---@return integer[]?
function M.counts_of(entry, list)
  list = list or "items"
  if not (entry and entry[list]) then
    return nil
  end
  local counts = {}
  for i = 1, #(list == "mine" and MINE_TIERS or TIERS) do
    counts[i] = 0
  end
  for _, it in ipairs(entry[list]) do
    counts[it.verdict.tier] = counts[it.verdict.tier] + 1
  end
  return counts
end

--- The cached counts for `dir`'s repo (see counts_of). A repo nobody has
--- asked about yet gets its first fetch kicked off, so a fresh tab's greeter
--- fills in without waiting for the timer.
---@param dir string
---@param list? "items"|"mine"
---@return integer[]?
function M.counts(dir, list)
  local key = M.key(dir)
  if not key then
    return nil
  end
  if not M.cache[key] then
    M.refresh(dir)
  end
  return M.counts_of(M.cache[key], list)
end

--- Refresh every repo with an open workspace tab.
function M.refresh_open()
  local seen = {}
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local dir = vim.fn.getcwd(-1, vim.api.nvim_tabpage_get_number(tab))
    local key = M.key(dir)
    if key and not seen[key] then
      seen[key] = true
      M.refresh(dir)
    end
  end
end

local timer ---@type uv.uv_timer_t?

--- Start the background refresh.
function M.setup()
  if timer then
    return
  end
  timer = assert(vim.uv.new_timer())
  timer:start(M.INTERVAL_MS, M.INTERVAL_MS, vim.schedule_wrap(M.refresh_open))
end

--- The preview's size line, markdown: "**+12 -3** in 4 files · …".
---@param size diffsize.Size?
---@return string
local function size_line(size)
  if not size then
    return ""
  end
  local adds, dels = diffsize.counts(size)
  return ("**%s %s**%s"):format(adds, dels, diffsize.detail(size))
end

---@param ms integer
---@return string
local function ago(ms)
  local min = math.floor(ms / 60000)
  return min < 1 and "just now" or ("%dm ago"):format(min)
end

---@class reviewqueue.View
---@field tiers { label: string, hl: string }[]
---@field title string
---@field empty string
---@field mine boolean

---@type table<"items"|"mine", reviewqueue.View>
local VIEWS = {
  items = {
    tiers = TIERS,
    title = "Review queue",
    empty = "nothing needs your review",
    mine = false,
  },
  mine = { tiers = MINE_TIERS, title = "My PRs", empty = "you have no open PRs here", mine = true },
}

--- The picker over one of a cached entry's lists.
---@param list "items"|"mine"
---@param entry reviewqueue.Entry
---@param dir string
local function show(list, entry, dir)
  local view, its = VIEWS[list], entry[list]
  if #its == 0 then
    vim.notify(view.empty, vim.log.levels.INFO, { title = view.title })
    return
  end
  -- The size columns are as wide as the widest size, so the titles line up.
  local adds_w, dels_w = 0, 0
  for _, it in ipairs(its) do
    if it.pr.size then
      local adds, dels = diffsize.counts(it.pr.size)
      adds_w, dels_w = math.max(adds_w, #adds), math.max(dels_w, #dels)
    end
  end
  -- Fresh tables each time: snacks adds its own fields to an item, and the
  -- cached list outlives this picker.
  local rows = {}
  for i, it in ipairs(its) do
    local pr = it.pr
    local head = {
      ("# #%d %s"):format(pr.number, pr.title),
      "",
      ("**%s** — %s"):format(view.tiers[it.verdict.tier].label, it.verdict.reason),
    }
    for _, note in ipairs(it.verdict.notes or {}) do
      head[#head + 1] = ""
      head[#head + 1] = note
    end
    rows[i] = {
      idx = i,
      pr = pr,
      verdict = it.verdict,
      text = ("#%d %s %s %s %s"):format(pr.number, pr.title, pr.author, pr.head, it.verdict.reason),
      preview = {
        ft = "markdown",
        text = table.concat(
          vim.list_extend(head, {
            "",
            ("by @%s · `%s` → `%s`"):format(pr.author, pr.head, pr.base),
            size_line(pr.size),
            pr.url,
            "",
            ((pr.body or ""):gsub("\r", "")),
          }),
          "\n"
        ),
      },
    }
  end
  Snacks.picker.pick({
    source = "reviewqueue",
    title = ("%s · %s/%s · %s"):format(
      view.title,
      entry.repo.owner,
      entry.repo.name,
      ago(vim.uv.now() - entry.at)
    ),
    items = rows,
    preview = "preview",
    format = function(item)
      local tier = view.tiers[item.verdict.tier]
      -- Additions right-aligned, deletions left: "  +12 -3   ".
      local adds, dels = "", ""
      if item.pr.size then
        adds, dels = diffsize.counts(item.pr.size)
      end
      local chunks = {
        { ("%-11s "):format(tier.label), tier.hl },
        { ("#%-5d "):format(item.pr.number), "SnacksPickerIdx" },
        { (" "):rep(adds_w - #adds) .. adds .. " ", "Added" },
        { dels .. (" "):rep(dels_w - #dels) .. "  ", "Removed" },
        { item.pr.title .. " " },
      }
      if not view.mine then -- they're all mine: the author says nothing
        chunks[#chunks + 1] = { "@" .. item.pr.author .. " ", "SnacksPickerComment" }
      end
      chunks[#chunks + 1] = { item.verdict.reason, "SnacksPickerComment" }
      return chunks
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        -- My own PR: review mode only when there are comments to answer,
        -- which is what shows them inline (nitpick).
        M.open(item.pr, dir, { review = not view.mine or item.verdict.review })
      end
    end,
    actions = {
      browse = function(_, item)
        if item then
          vim.ui.open(item.pr.url)
        end
      end,
    },
    win = {
      input = {
        keys = { ["<c-o>"] = { "browse", mode = { "n", "i" }, desc = "Open PR in browser" } },
      },
    },
  })
end

--- <leader>rq (the review queue) / <leader>rm (my PRs) for the current repo.
--- From the cache when there is one (refreshed behind it if stale);
--- otherwise fetched now.
---@param list? "items"|"mine" default "items"
function M.pick(list)
  list = list or "items"
  local title = VIEWS[list].title
  local dir = vim.fn.getcwd()
  local key = M.key(dir)
  if not key then
    vim.notify("not in a repository", vim.log.levels.WARN, { title = title })
    return
  end
  local entry = M.cache[key]
  if entry and entry[list] then
    show(list, entry, dir)
    if vim.uv.now() - entry.at > STALE_MS then
      M.refresh(dir)
    end
    return
  end
  local id = "reviewqueue"
  vim.notify(
    ("fetching %s…"):format(title:lower()),
    vim.log.levels.INFO,
    { id = id, title = title }
  )
  M.refresh(dir, function(fresh)
    if fresh.err then
      vim.notify(fresh.err, vim.log.levels.ERROR, { id = id, title = title })
      return
    end
    Snacks.notifier.hide(id)
    show(list, fresh, dir)
  end)
end

return M
