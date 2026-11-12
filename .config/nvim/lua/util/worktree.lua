-- Git worktrees as workspace tabs: pick a branch, get a worktree for it, open it
-- as its own project tabpage (config/workspace.lua) -- in one keystroke.
--
-- The point is that a worktree IS a project directory, so it slots straight into
-- the one-project-per-tabpage model: an agent can churn on a branch in one tab
-- while you keep working on main in another, with separate terminals, explorer
-- and buffer list, and no stashing.
--
-- Worktrees live in `<main worktree>/.worktrees/<branch>` -- inside the repo so
-- they travel with it and are trivially findable, kept out of `git status` by the
-- global gitignore entry (base.nix, programs.git.ignores). Deliberately NOT a
-- sibling directory: that scatters half-finished checkouts through the parent of
-- every repo and pollutes zoxide's list with them.
--
-- With agent_worktrees on (M.setup) a worktree belongs to an agent instead of a
-- branch: `.worktrees/<agent's pet name>`, where the agent checks out whatever
-- branches it needs, so a stack of PRs is branch switches in one checkout.

local M = {}

---@class worktree.Options
---@field agent_worktrees boolean one worktree per agent, named after it
---@field claude_projects string Claude's per-directory state (~/.claude/projects)
local options = { agent_worktrees = false, claude_projects = vim.fn.expand("~/.claude/projects") }

--- Set once at startup, from the environment (init.lua).
---@param opts worktree.Options
function M.setup(opts)
  options = vim.tbl_extend("force", options, opts)
end

--- Directory name for a branch's worktree. Branch names are paths (`feat/x`),
--- which would nest -- and leave empty `feat/` directories behind on removal --
--- so flatten to a single component.
---@param branch string
---@return string
function M.slug(branch)
  return (branch:gsub("^remotes/", ""):gsub("/", "-"))
end

--- Run git in `cwd`. Returns trimmed stdout, or nil plus stderr on failure.
---@param cwd string
---@param args string[]
---@return string? out, string? err
local function git(cwd, args)
  local res = vim.system(vim.list_extend({ "git" }, args), { cwd = cwd, text = true }):wait()
  if res.code ~= 0 then
    return nil, vim.trim(res.stderr or "")
  end
  return vim.trim(res.stdout or "")
end

--- Percent complete from one line of git's progress output
--- (`Updating files:  45% (3600/7941)`, `Receiving objects: 12% (...)`), or nil
--- for any other line. Git emits these `\r`-separated, and only to a terminal
--- (see git_async).
---@param line string
---@return integer? percent, string? phase
function M.progress(line)
  local phase, pct = line:match("^%s*([%a ]+):%s+(%d+)%%")
  if pct then
    return tonumber(pct), phase
  end
  return nil
end

--- Errors and warnings go through vim.notify so they land in the notifier's
--- history; progress does not (see busy()).
---@param msg string
---@param level integer
local function status(msg, level)
  vim.notify(msg, level, { title = "worktree" })
end

-- The progress indicator: one line in a small float at the centre of the
-- editor, not a toast. A toast in the corner reads as "something happened";
-- this has to read as "the editor is busy" -- a checkout of a large tree takes
-- seconds (longer cold) and nothing else visible changes until the tab appears.
-- Not focusable and never entered, so keys keep going to the editor.
local busy_win ---@type snacks.win?
local BUSY_WIDTH = 50

---@param msg string
local function busy(msg)
  msg = vim.fn.strcharpart(msg, 0, BUSY_WIDTH - 2)
  local pad = math.floor((BUSY_WIDTH - vim.fn.strdisplaywidth(msg)) / 2)
  local line = (" "):rep(pad) .. msg
  if busy_win and busy_win:valid() then
    vim.api.nvim_buf_set_lines(busy_win.buf, 0, -1, false, { line })
    return
  end
  busy_win = Snacks.win({
    relative = "editor",
    position = "float",
    width = BUSY_WIDTH,
    height = 1,
    border = "rounded",
    title = " worktree ",
    title_pos = "center",
    text = { line },
    focusable = false,
    enter = false,
    backdrop = false,
    bo = { buftype = "nofile", bufhidden = "wipe" },
    wo = { cursorline = false, winhighlight = "NormalFloat:Normal,FloatBorder:FloatBorder" },
  })
end

local function busy_done()
  if busy_win then
    busy_win:close()
    busy_win = nil
  end
end

--- Run git in `cwd` WITHOUT blocking the editor. Progress lines are turned into
--- `label 45%` updates on the status toast; `cb(out, err)` runs on the main
--- loop with the same contract as `git()`. Everything cheap (listing refs) can
--- afford to block; a checkout of a large tree (seconds, longer cold) cannot --
--- with the loop blocked no notification could even be drawn.
---
--- Runs under a pty, not vim.system: git only draws a progress meter when stderr
--- is a terminal, and `worktree add` has no flag to force it (its internal reset
--- does not inherit one). The pty merges stdout and stderr, so the last
--- non-progress line stands in for both the result and the error message.
--- GIT_PROGRESS_DELAY=0 drops git's two-second grace period before the meter
--- appears, so the toast shows a percentage at once.
---@param cwd string
---@param args string[]
---@param label string what the toast says while this runs
---@param cb fun(out: string?, err: string?)
local function git_async(cwd, args, label, cb)
  busy(label .. "…")
  local lines = {}
  vim.fn.jobstart(vim.list_extend({ "git" }, args), {
    cwd = cwd,
    pty = true,
    width = 200, -- wide enough that git never truncates a progress line
    env = { GIT_PROGRESS_DELAY = "0" },
    on_stdout = function(_, data)
      for _, chunk in ipairs(data) do
        for line in chunk:gmatch("[^\r\n]+") do
          local pct = M.progress(line)
          if pct then
            busy(("%s… %d%%"):format(label, pct))
          else
            lines[#lines + 1] = line
          end
        end
      end
    end,
    on_exit = function(_, code)
      local last = vim.trim(lines[#lines] or "")
      -- The float stays up through the callback: building the tab (greeter,
      -- explorer, shell) is part of "busy" from where the user sits.
      local ok, err
      if code ~= 0 then
        ok, err = pcall(cb, nil, last ~= "" and last or ("exit " .. code))
      else
        ok, err = pcall(cb, last)
      end
      busy_done()
      if not ok then
        error(err, 0)
      end
    end,
  })
end
M.git_async = git_async

--- The repo's MAIN worktree for `dir` (the one holding the real .git directory),
--- which is where `.worktrees/` lives. Derived from --git-common-dir rather than
--- --show-toplevel so that calling this from inside a worktree tab still creates
--- the next worktree alongside its siblings, not nested inside this one.
---@param dir string
---@return string? root, string? err
function M.root(dir)
  local common, err = git(dir, { "rev-parse", "--path-format=absolute", "--git-common-dir" })
  if not common then
    return nil, err or "not a git repository"
  end
  return (vim.fs.dirname(common):gsub("/$", ""))
end

--- Resolve a picked-or-pasted name to a ref the repo actually has. GitHub's UI
--- copies the bare branch name (`feat/x`), not a remote-qualified ref, so a name
--- that isn't a local branch is checked against every remote's tracking refs
--- before we conclude it's new.
---@param branch string as picked/pasted ("x", "origin/x", "remotes/origin/x")
---@param locals table<string, true> existing local branch names
---@param remote_refs table<string, true> remote-tracking refs ("origin/x")
---@return string? ref the branch as an existing local or remote-tracking ref
function M.resolve(branch, locals, remote_refs)
  branch = branch:gsub("^remotes/", "")
  if locals[branch] or remote_refs[branch] then
    return branch
  end
  -- origin first, so a fork remote carrying the same branch can't win by
  -- table-iteration luck; any other remote is only reachable when unambiguous.
  if remote_refs["origin/" .. branch] then
    return "origin/" .. branch
  end
  for ref in pairs(remote_refs) do
    if ref:match("^[^/]+/(.+)$") == branch then
      return ref
    end
  end
  return nil
end

--- The local branch a worktree for `branch` ends up with checked out. A remote
--- ref (`origin/x`) gets a local tracking branch `x` (see add_args), so the
--- project directory and the existing-worktree lookup must use that name, not
--- the remote-qualified one -- unless a local branch literally named `origin/x`
--- exists, which wins just as it does in add_args.
---@param branch string branch name as picked ("x", "origin/x", "remotes/origin/x")
---@param locals table<string, true> set of existing local branch names
---@param remotes table<string, true> set of known remote names ("origin")
---@return string
function M.local_name(branch, locals, remotes)
  branch = branch:gsub("^remotes/", "")
  if locals[branch] then
    return branch
  end
  local remote, rest = branch:match("^([^/]+)/(.+)$")
  if remote and remotes[remote] then
    return rest
  end
  return branch
end

--- `git worktree add` arguments for putting `branch` at `path`.
---
--- Three cases, and they need different flags: an existing local branch is just
--- checked out; a remote-tracking ref (`origin/x`, as listed by an --all branch
--- picker) needs a local branch created to track it, since a worktree can't sit
--- on a remote ref; anything else is a name you typed, i.e. a new branch off HEAD.
---@param branch string branch name as picked ("x", "origin/x", "remotes/origin/x")
---@param path string worktree directory to create
---@param locals table<string, true> set of existing local branch names
---@param remotes table<string, true> set of known remote names ("origin")
---@return string[]
function M.add_args(branch, path, locals, remotes)
  branch = branch:gsub("^remotes/", "")
  if locals[branch] then
    return { "worktree", "add", path, branch }
  end
  local remote, rest = branch:match("^([^/]+)/(.+)$")
  if remote and remotes[remote] then
    -- A local branch by the tracking name already exists (picked as `origin/x`
    -- with `x` local): -b would fail with "branch already exists", so check the
    -- local branch out instead.
    if locals[rest] then
      return { "worktree", "add", path, rest }
    end
    return { "worktree", "add", "--track", "-b", rest, path, branch }
  end
  return { "worktree", "add", "-b", branch, path }
end

--- The personal branch prefix, lazygit's `git.branchPrefix`: every branch made
--- from nvim starts with it, so a new-name prompt is pre-filled with it.
M.prefix = "rkk/"

--- Where `local_branch`'s worktree is, or is to be made: wherever git already has
--- it checked out, else under `<root>/.worktrees/`.
---@param root string the main worktree (M.root)
---@param local_branch string
---@param worktrees table<string, string> existing worktrees, branch -> path
---@return string
function M.path(root, local_branch, worktrees)
  return worktrees[local_branch] or root .. "/.worktrees/" .. M.slug(local_branch)
end

--- Existing worktrees of the repo at `dir`, as branch -> path. Branch is the
--- short name (`refs/heads/x` -> `x`); detached worktrees are skipped, having no
--- branch to pick them by.
---@param dir string
---@return table<string, string>
local function existing(dir)
  local out = git(dir, { "worktree", "list", "--porcelain" }) or ""
  local map, path = {}, nil
  for line in vim.gsplit(out, "\n") do
    local p = line:match("^worktree (.+)$")
    if p then
      path = p
    end
    local ref = line:match("^branch refs/heads/(.+)$")
    if ref and path then
      map[ref] = path
    end
  end
  return map
end

---@param dir string
---@return table<string, true>
local function local_branches(dir)
  local out = git(dir, { "for-each-ref", "--format=%(refname:short)", "refs/heads" }) or ""
  local set = {}
  for name in vim.gsplit(out, "\n") do
    if name ~= "" then
      set[name] = true
    end
  end
  return set
end

---@param dir string
---@return table<string, true>
--- Remote-tracking refs as a set of short names ("origin/x"). `HEAD` symrefs
--- (origin/HEAD) are skipped: they alias another branch and would only add a
--- confusing duplicate for resolve() to hit.
---@param dir string
---@return table<string, true>
local function remote_refs(dir)
  local out = git(dir, { "for-each-ref", "--format=%(refname:short)", "refs/remotes" }) or ""
  local set = {}
  for name in vim.gsplit(out, "\n") do
    if name ~= "" and not name:match("/HEAD$") then
      set[name] = true
    end
  end
  return set
end

local function remote_names(dir)
  local set = {}
  for name in vim.gsplit(git(dir, { "remote" }) or "", "\n") do
    if name ~= "" then
      set[name] = true
    end
  end
  return set
end

local checkout, abandon, agent_name_for

--- Open `branch`'s worktree as a new workspace tab, creating it if needed.
--- Reuses whatever already exists: a worktree git already knows about, or a
--- directory left behind at the expected path.
---@param branch string
---@param dir? string a directory inside the repo (default: the tab's cwd)
---@param opts? worktree.OpenOpts
function M.open(branch, dir, opts)
  branch = vim.trim(branch)
  if branch == "" then
    return
  end
  local target, err = M.target(branch, dir or vim.fn.getcwd())
  if not target then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end
  M.go(target, opts or {})
end

---@class worktree.OpenOpts
---@field on_open? fun(path: string) runs once the worktree is checked out (the tab opens before that)
---@field background? boolean leave focus where it is (config.workspace's option of that name)

--- Where opening a branch lands, and what has to happen there first.
---@class worktree.Target
---@field kind "open"|"create" open an existing directory, or make the worktree first
---@field path string
---@field name? string the agent a new agent worktree is named after
---@field root string the main worktree
---@field branch string as picked
---@field resolved? string the branch as an existing ref (M.resolve)
---@field locals table<string, true>
---@field remotes table<string, true>

--- Decide where `branch` opens, without touching anything yet: open_for_agent
--- has to answer with the path (and agent name) before the work happens.
---@param branch string as picked
---@param dir string a directory inside the repo
---@return worktree.Target? target, string? err
function M.target(branch, dir)
  local root, err = M.root(dir)
  if not root then
    return nil, err or "not a git repository"
  end
  local t =
    { root = root, branch = branch, locals = local_branches(root), remotes = remote_names(root) }
  t.resolved = M.resolve(branch, t.locals, remote_refs(root))
  -- A fetch can only turn `x` into `origin/x`, whose local name is still `x`.
  local local_branch = M.local_name(t.resolved or branch, t.locals, t.remotes)
  local worktrees = existing(root)
  if not options.agent_worktrees or worktrees[local_branch] then
    t.path = M.path(root, local_branch, worktrees)
    t.kind = vim.fn.isdirectory(t.path) == 1 and "open" or "create"
    return t
  end
  local name, name_err = agent_name_for(root)
  if not name then
    return nil, name_err
  end
  t.kind, t.path, t.name = "create", M.agent_path(root, name), name
  return t
end

--- Carry out a target (M.target) as a workspace tab.
---@param t worktree.Target
---@param opts worktree.OpenOpts
function M.go(t, opts)
  local function checked_out()
    if opts.on_open then
      opts.on_open(t.path)
    end
  end

  M.touch(t.path)
  if t.kind == "open" then
    require("config.workspace").open(t.path, { tab = true, background = opts.background })
    return checked_out()
  end
  -- git checks out into an empty directory, so the tab needn't wait for it.
  vim.fn.mkdir(t.path, "p")
  require("config.workspace").open(t.path, {
    tab = true,
    background = opts.background,
    until_ready = function(ready)
      checkout(t.root, t.branch, t.resolved, t.path, t.locals, t.remotes, function(err)
        if err then
          return abandon(t.path, err)
        end
        ready()
        checked_out()
      end)
    end,
  })
end

--- An agent's worktree directory.
---@param root string the main worktree
---@param name string the agent's name
---@return string
function M.agent_path(root, name)
  return root .. "/.worktrees/" .. name
end

--- Where Claude keeps its state for sessions started in `path`: the absolute
--- path with every character but letters and digits made `-`.
---@param projects string Claude's projects directory
---@param path string
---@return string
function M.claude_project(projects, path)
  return projects .. "/" .. path:gsub("[^%w]", "-")
end

--- The first of `candidates` that isn't taken, or nil when all are.
---@param candidates string[]
---@param taken fun(name: string): boolean
---@return string?
function M.free_name(candidates, taken)
  for _, name in ipairs(candidates) do
    if name ~= "" and not taken(name) then
      return name
    end
  end
end

-- Candidates drawn per new agent: pet names collide rarely, so one batch is plenty.
local NAME_CANDIDATES = 20

--- A pet name (as session-identity names sessions) for a new agent in `root`'s
--- repo, unused as a worktree and by any Claude history, so the agent can't
--- pick up a stranger's conversation through `claude --continue`.
---@param root string
---@return string? name, string? err
agent_name_for = function(root)
  local cmd =
    { "petname", "--lists", "small", "--words", "2", "--count", tostring(NAME_CANDIDATES) }
  local ok, res = pcall(function()
    return vim.system(cmd, { text = true }):wait()
  end)
  if not ok or res.code ~= 0 then
    return nil, "petname: " .. (ok and vim.trim(res.stderr or "") or tostring(res))
  end
  local name = M.free_name(vim.split(vim.trim(res.stdout), "\n"), function(n)
    local path = M.agent_path(root, n)
    return vim.uv.fs_stat(path) ~= nil
      or vim.uv.fs_stat(M.claude_project(options.claude_projects, path)) ~= nil
  end)
  if not name then
    return nil, ("no free agent name in %d tries"):format(NAME_CANDIDATES)
  end
  return name
end

--- Put `branch`'s worktree at `path`, then `cb(err)`. A name that matches
--- nothing local or remote-tracking may simply not be fetched yet -- the "paste
--- a branch name straight from GitHub" case -- so try a targeted fetch from
--- origin before concluding it's a new branch off HEAD.
---@param root string the main worktree
---@param branch string as picked
---@param resolved string? the branch as an existing ref (M.resolve)
---@param path string an empty directory
---@param locals table<string, true>
---@param remotes table<string, true>
---@param cb fun(err: string?)
checkout = function(root, branch, resolved, path, locals, remotes, cb)
  local function add(ref)
    local label = "checking out " .. M.local_name(ref, locals, remotes)
    git_async(root, M.add_args(ref, path, locals, remotes), label, function(_, err)
      cb(err and ("git worktree add: " .. err))
    end)
  end
  if resolved or branch:find("%s") then
    return add(resolved or branch)
  end
  local short = branch:gsub("^remotes/", "")
  git_async(root, { "fetch", "origin", short }, "fetching origin/" .. short, function(ok)
    -- A failed fetch just means the name is new: fall through to -b.
    add(ok and M.resolve(branch, locals, remote_refs(root)) or branch)
  end)
end

--- A checkout failed: report it and take down the tab opened for it, and the
--- directory made for it (only if git left it empty).
---@param path string
---@param err string
abandon = function(path, err)
  status(err, vim.log.levels.ERROR)
  local tab = require("config.workspace").find(path)
  if tab and #vim.api.nvim_list_tabpages() > 1 then
    vim.cmd.tabclose(vim.api.nvim_tabpage_get_number(tab))
  end
  vim.fn.delete(path, "d")
end

--- Prompt for a name and open a worktree tab for it: the picker's <CR> only
--- takes typed text when nothing fuzzy-matches it, so a new branch name gets its
--- own entry point.
--- M.open branches an unknown name off the main worktree's HEAD. The prompt
--- starts with the prefix, as lazygit's does; delete it for a shared branch.
function M.new()
  local cwd = vim.fn.getcwd()
  vim.ui.input({ prompt = "New branch: ", default = M.prefix }, function(input)
    local branch = vim.trim(input or "")
    if branch ~= "" then
      M.open(branch, cwd)
    end
  end)
end

--- M.open, callable from a lazygit custom command over `nvim --remote-expr`.
--- The float has to hide first (the new tab would otherwise be built underneath
--- it), and the real work is deferred so the RPC reply returns immediately
--- instead of holding lazygit while worktree creation (possibly a fetch) runs.
---@param branch string
---@return string '' -- --remote-expr prints the expression's value; keep it empty
function M.open_from_lazygit(branch)
  local cwd = vim.fn.getcwd()
  require("util.lazygit").hide()
  vim.schedule(function()
    M.open(branch, cwd)
  end)
  return ""
end

--- M.open for another program (.local/bin/worktree-tab) over `nvim
--- --remote-expr`. Answers at once with where the worktree is to be, so the
--- caller can wait for the Claude that starts there and hand it work; the tab
--- opens at once, its Claude once the (async) checkout is done. A new agent
--- worktree's answer carries the name its Claude will take.
---@param branch string
---@param cwd string a directory inside the repo
---@return string json: {"path": ..., "name"?: ...} or {"error": ...}
function M.open_for_agent(branch, cwd)
  local target, err = M.target(vim.trim(branch), cwd)
  if not target then
    return vim.json.encode({ error = err })
  end
  vim.schedule(function()
    M.go(target, { background = true })
  end)
  return vim.json.encode({ path = target.path, name = target.name })
end

--- Pick a branch to open as a worktree tab.
---
--- snacks' git_branches picker supplies the list (with `all` so remote branches
--- are offered -- picking one up as a new worktree is exactly the "review a PR
--- without touching my checkout" case). Only the confirm changes: the default
--- checks the branch out in place, which is the thing worktrees exist to avoid.
---
--- `<CR>` on no match creates a branch named by whatever you typed, so a new
--- branch needs no separate keymap: type the name, nothing matches, press enter.
--- Recently opened worktrees, as path -> unix time of the last open. Persisted
--- in the state dir so the ordering survives restarts. This is our own record
--- rather than the reflog (lazygit's recency source): `worktree add` writes to
--- the NEW worktree's HEAD reflog, so the main one never sees a checkout and
--- the reflog says nothing about which branch you were in yesterday.
local recent_file = vim.fn.stdpath("state") .. "/worktree-recent.json"

--- The recency record, path -> unix time of the last open.
---@return table<string, integer>
function M.recent_load()
  local f = io.open(recent_file, "r")
  if not f then
    return {}
  end
  local ok, data = pcall(vim.json.decode, f:read("*a"))
  f:close()
  return ok and type(data) == "table" and data or {}
end

--- Record that `path`'s worktree was opened just now.
---@param path string
function M.touch(path)
  local recent = M.recent_load()
  recent[path] = os.time()
  local f = io.open(recent_file, "w")
  if f then
    f:write(vim.json.encode(recent))
    f:close()
  end
end

---@class worktree.Candidate
---@field branch string short ref name ("x" or "origin/x")
---@field remote? boolean a remote-tracking ref (refs/remotes)
---@field name? string display name when it differs from branch ("x" for "origin/x")
---@field time integer committer date, unix time (sort key)
---@field date? string committer date as shown ("3 days ago")
---@field worktree? string path of an existing worktree for this branch
---@field current? boolean

--- Picker order. Branches that have a worktree come first, most recently opened
--- first (never-opened ones after, by commit date); every other branch follows
--- by commit date, newest first. A remote ref whose bare name is also a local
--- branch is dropped: it's the same branch twice, and resolve() maps the local
--- name back to the remote when needed.
---@param items worktree.Candidate[]
---@param recent table<string, integer> worktree path -> last opened
---@return worktree.Candidate[]
function M.order(items, recent)
  local locals = {}
  for _, it in ipairs(items) do
    if not it.remote then
      locals[it.branch] = true
    end
  end
  -- Remote refs are shown by their bare name (the `origin/` is noise), so a
  -- branch on two remotes also collapses to one row: origin's, else the first.
  local out, seen = {}, {}
  table.sort(items, function(a, b)
    local ao, bo = a.branch:match("^origin/") ~= nil, b.branch:match("^origin/") ~= nil
    if ao ~= bo then
      return ao
    end
    return a.branch < b.branch
  end)
  for _, it in ipairs(items) do
    local rest = it.remote and it.branch:match("^[^/]+/(.+)$")
    if not rest then
      out[#out + 1] = it
    elseif not locals[rest] and not seen[rest] then
      seen[rest] = true
      it.name = rest
      out[#out + 1] = it
    end
  end
  table.sort(out, function(a, b)
    if (a.worktree ~= nil) ~= (b.worktree ~= nil) then
      return a.worktree ~= nil
    end
    local ra, rb = a.worktree and recent[a.worktree] or 0, b.worktree and recent[b.worktree] or 0
    if ra ~= rb then
      return ra > rb
    end
    if a.time ~= b.time then
      return a.time > b.time
    end
    return a.branch < b.branch
  end)
  return out
end

--- Every branch, local and remote-tracking, with what the picker needs.
---@param root string
---@return worktree.Candidate[]
local function candidates(root)
  local fmt =
    "%(refname)%09%(refname:short)%09%(objectname:short)%09%(committerdate:unix)%09%(committerdate:relative)%09%(HEAD)%09%(contents:subject)"
  local out = git(root, { "for-each-ref", "--format=" .. fmt, "refs/heads", "refs/remotes" }) or ""
  local wts = existing(root)
  local items = {}
  for line in vim.gsplit(out, "\n") do
    local ref, branch, commit, time, date, head, msg =
      line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)\t(%d+)\t([^\t]+)\t([^\t]*)\t(.*)$")
    if branch and not ref:match("/HEAD$") then
      items[#items + 1] = {
        branch = branch,
        remote = ref:match("^refs/remotes/") ~= nil,
        commit = commit,
        time = tonumber(time),
        date = date,
        msg = msg,
        current = head == "*",
        worktree = wts[branch],
      }
    end
  end
  return items
end

--- <M-b>w: pick a branch, get its worktree as a tab. Recently opened
--- worktrees float to the top (see M.order); typing a name that matches nothing
--- creates a new branch off HEAD.
function M.pick()
  local cwd = vim.fn.getcwd()
  local root, err = M.root(cwd)
  if not root then
    vim.notify(err or "not a git repository", vim.log.levels.ERROR)
    return
  end
  local items = M.order(candidates(root), M.recent_load())
  for i, it in ipairs(items) do
    it.text = (it.name or it.branch) .. " " .. (it.msg or "")
    it.cwd = root
    it.idx = i
  end
  Snacks.picker.pick({
    source = "worktree",
    title = "Worktrees",
    items = items,
    format = function(item, picker)
      local ret = Snacks.picker.format.git_branch(
        vim.tbl_extend("force", item, { branch = item.name or item.branch }),
        picker
      )
      -- Mark rows that already have a worktree: picking one is a plain tab open.
      table.insert(ret, 2, { item.worktree and "\u{f0e8e} " or "   ", "SnacksPickerGitBranch" })
      return ret
    end,
    preview = "git_log",
    confirm = function(picker, item)
      local pattern = picker:filter().pattern
      picker:close()
      local branch = item and item.branch or pattern
      if branch then
        M.open(branch, cwd)
      end
    end,
  })
end

return M
