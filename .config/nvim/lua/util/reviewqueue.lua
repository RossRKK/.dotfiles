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

local M = {}

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
---@field reviewed_by_me boolean? found via `reviewed-by:@me`

---@class reviewqueue.Ctx
---@field me string
---@field my_teams table<string, true> lowercased slugs, ancestors included
---@field exclude table<string, true> lowercased slugs
---@field rules reviewqueue.Rule[]
---@field teams_of table<string, table<string, true>> login -> its team slugs

---@class reviewqueue.Verdict
---@field tier 1|2|3
---@field reason string

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

--- Verdicts in display order: tier, then oldest PR first -- a queue, so the
--- one that's waited longest is at the front.
---@param items { pr: reviewqueue.PR, verdict: reviewqueue.Verdict }[]
function M.sort(items)
  table.sort(items, function(a, b)
    if a.verdict.tier ~= b.verdict.tier then
      return a.verdict.tier < b.verdict.tier
    end
    return a.pr.number < b.pr.number
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
    reviewed_by_me = reviewed_by_me,
  }
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
  files(first: 100) { pageInfo { hasNextPage endCursor } nodes { path } }
]]

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
      files(first: 100, after: $after) { pageInfo { hasNextPage endCursor } nodes { path } }
    }
  }
}]]

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
  -- Drafts and my own PRs never need my review; filtering here also spares
  -- paging a big draft's file list.
  local q = ("repo:%s/%s is:pr is:open draft:false -author:@me %s"):format(
    repo.owner,
    repo.name,
    qualifier
  )
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
---@return table[] nodes
local function details(repo, numbers)
  local fields = {}
  for i, n in ipairs(numbers) do
    fields[i] = ("p%d: pullRequest(number: %d) { %s }"):format(i, n, PR_FIELDS)
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

--- Everything the picker shows, for the repo at `dir`, classified and sorted.
---@param dir string
---@return { pr: reviewqueue.PR, verdict: reviewqueue.Verdict }[] items, { owner: string, name: string } repo
function M.fetch(dir)
  local view = run({ "gh", "repo", "view", "--json", "owner,name" }, { cwd = dir })
  local ok, info = pcall(vim.json.decode, view.stdout or "")
  if view.code ~= 0 or not ok then
    error("not a GitHub repo: " .. vim.trim(view.stderr or ""), 0)
  end
  local repo = { owner = info.owner.login, name = info.name }

  local first = parallel({
    function()
      return graphql("{ viewer { login } }").viewer.login
    end,
    function()
      return search(repo, "reviewed-by:@me")
    end,
    function()
      return search(repo, "review-requested:@me")
    end,
    function()
      return excluded(dir)
    end,
  })
  local me, reviewed, requested, exclude = first[1], first[2], first[3], first[4]

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

  local batches = {}
  for i = 1, #numbers, 10 do
    local batch = vim.list_slice(numbers, i, i + 9)
    batches[#batches + 1] = function()
      return details(repo, batch)
    end
  end
  local prs = {}
  for _, nodes in ipairs(parallel(batches)) do
    for _, node in ipairs(nodes) do
      prs[#prs + 1] = M.from_node(node, reviewed_set[node.number] == true)
    end
  end

  local bases, approvers = {}, { [me] = true }
  for _, pr in ipairs(prs) do
    bases[pr.base] = true
    for _, r in ipairs(pr.reviews) do
      if r.state == "APPROVED" then
        approvers[r.author] = true
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
  local items = {}
  for _, pr in ipairs(prs) do
    rules[pr.base] = rules[pr.base] or M.parse_codeowners(owners_text[pr.base] or "")
    local verdict = M.classify(pr, {
      me = me,
      my_teams = teams[lower(me)] or {},
      exclude = exclude,
      rules = rules[pr.base],
      teams_of = teams,
    })
    if verdict then
      items[#items + 1] = { pr = pr, verdict = verdict }
    end
  end
  return M.sort(items), repo
end

-- ---------------------------------------------------------------------------
-- Opening a PR for review

--- Fetch the PR head so the worktree starts at what's actually on the PR (a
--- tier-2 PR is there BECAUSE it moved), open it as a workspace tab, and turn
--- review mode on there against the PR's own base.
---@param pr reviewqueue.PR
---@param dir string a directory inside the repo
function M.open(pr, dir)
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

-- ---------------------------------------------------------------------------
-- Cache: the queue is refreshed in the background (setup()), so the picker
-- opens at once and the greeter can show counts without a fetch of its own.

---@class reviewqueue.Entry
---@field items { pr: reviewqueue.PR, verdict: reviewqueue.Verdict }[]?
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
    local ok, items, repo = pcall(M.fetch, key)
    local entry = ok and { items = items, repo = repo, at = vim.uv.now() }
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
    if not vim.deep_equal(M.counts_of(prev), M.counts_of(entry)) then
      pcall(function()
        require("config.greeter").update_dashboards()
      end)
    end
  end)()
end

--- Items per tier, or nil when there's no list.
---@param entry reviewqueue.Entry?
---@return integer[]?
function M.counts_of(entry)
  if not (entry and entry.items) then
    return nil
  end
  local counts = { 0, 0, 0 }
  for _, it in ipairs(entry.items) do
    counts[it.verdict.tier] = counts[it.verdict.tier] + 1
  end
  return counts
end

--- The cached counts for `dir`'s repo (see counts_of). A repo nobody has
--- asked about yet gets its first fetch kicked off, so a fresh tab's greeter
--- fills in without waiting for the timer.
---@param dir string
---@return integer[]?
function M.counts(dir)
  local key = M.key(dir)
  if not key then
    return nil
  end
  if not M.cache[key] then
    M.refresh(dir)
  end
  return M.counts_of(M.cache[key])
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

---@param ms integer
---@return string
local function ago(ms)
  local min = math.floor(ms / 60000)
  return min < 1 and "just now" or ("%dm ago"):format(min)
end

--- The picker over a cached entry.
---@param entry reviewqueue.Entry
---@param dir string
local function show(entry, dir)
  if #entry.items == 0 then
    vim.notify("nothing needs your review", vim.log.levels.INFO, { title = "review queue" })
    return
  end
  -- Fresh tables each time: snacks adds its own fields to an item, and the
  -- cached list outlives this picker.
  local rows = {}
  for i, it in ipairs(entry.items) do
    local pr = it.pr
    rows[i] = {
      idx = i,
      pr = pr,
      verdict = it.verdict,
      text = ("#%d %s %s %s %s"):format(pr.number, pr.title, pr.author, pr.head, it.verdict.reason),
      preview = {
        ft = "markdown",
        text = table.concat({
          ("# #%d %s"):format(pr.number, pr.title),
          "",
          ("**%s** — %s"):format(TIERS[it.verdict.tier].label, it.verdict.reason),
          "",
          ("by @%s · `%s` → `%s`"):format(pr.author, pr.head, pr.base),
          pr.url,
          "",
          (pr.body or ""):gsub("\r", ""),
        }, "\n"),
      },
    }
  end
  Snacks.picker.pick({
    source = "reviewqueue",
    title = ("Review queue · %s/%s · %s"):format(
      entry.repo.owner,
      entry.repo.name,
      ago(vim.uv.now() - entry.at)
    ),
    items = rows,
    preview = "preview",
    format = function(item)
      local tier = TIERS[item.verdict.tier]
      return {
        { ("%-11s "):format(tier.label), tier.hl },
        { ("#%-5d "):format(item.pr.number), "SnacksPickerIdx" },
        { item.pr.title .. " " },
        { "@" .. item.pr.author .. " ", "SnacksPickerComment" },
        { item.verdict.reason, "SnacksPickerComment" },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        M.open(item.pr, dir)
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

--- <leader>rq: the review queue for the current repo. From the cache when
--- there is one (refreshed behind it if stale); otherwise fetched now.
function M.pick()
  local dir = vim.fn.getcwd()
  local key = M.key(dir)
  if not key then
    vim.notify("not in a repository", vim.log.levels.WARN, { title = "review queue" })
    return
  end
  local entry = M.cache[key]
  if entry and entry.items then
    show(entry, dir)
    if vim.uv.now() - entry.at > STALE_MS then
      M.refresh(dir)
    end
    return
  end
  local id = "reviewqueue"
  vim.notify("fetching review queue…", vim.log.levels.INFO, { id = id, title = "review queue" })
  M.refresh(dir, function(fresh)
    if fresh.err then
      vim.notify(fresh.err, vim.log.levels.ERROR, { id = id, title = "review queue" })
      return
    end
    Snacks.notifier.hide(id)
    show(fresh, dir)
  end)
end

return M
