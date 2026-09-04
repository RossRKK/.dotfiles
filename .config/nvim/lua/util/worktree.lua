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

local M = {}

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

--- `git worktree add` arguments for forking: a NEW branch at an explicit start
--- point. add_args deliberately branches new names off the main worktree's HEAD
--- (its git runs in root); a fork must instead start at the worktree the user is
--- sitting in, so the base commit is passed explicitly.
---@param branch string new branch name
---@param path string worktree directory to create
---@param base string commit the new branch starts at
---@return string[]
function M.fork_args(branch, path, base)
  return { "worktree", "add", "-b", branch, path, base }
end

--- The suggested branch name a fork's input prompt is pre-filled with: the
--- branch being forked, always under the personal `rkk/` prefix (not doubled if
--- already there), with `-fork` appended so the fork reads as one -- numbered
--- (-fork-2, -fork-3, …) past names already taken, so accepting the suggestion
--- never hands git a branch that exists.
---@param branch string? the current branch ("HEAD" or nil when detached)
---@param locals table<string, true> existing local branch names
---@return string
function M.fork_name(branch, locals)
  if not branch or branch == "" or branch == "HEAD" then
    branch = "fork"
  else
    branch = branch:gsub("^rkk/", "") .. "-fork"
  end
  local name = "rkk/" .. branch
  local n = 2
  while locals[name] do
    name = ("rkk/%s-%d"):format(branch, n)
    n = n + 1
  end
  return name
end

--- The shell command that forks a Claude Code session: same history, new
--- session id, leaving the original session untouched.
---@param session string session id (a UUID, so no quoting needed)
---@return string
function M.fork_cmd(session)
  return ("claude --resume %s --fork-session"):format(session)
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

--- Open `branch`'s worktree as a new workspace tab, creating it if needed.
--- Reuses whatever already exists: a worktree git already knows about, or a
--- directory left behind at the expected path.
---@param branch string
---@param dir? string a directory inside the repo (default: the tab's cwd)
function M.open(branch, dir)
  branch = vim.trim(branch)
  if branch == "" then
    return
  end
  dir = dir or vim.fn.getcwd()

  local root, err = M.root(dir)
  if not root then
    vim.notify(err or "not a git repository", vim.log.levels.ERROR)
    return
  end

  local locals = local_branches(root)
  local remotes = remote_names(root)

  -- Second half: the branch is now known (or known to be new); create the
  -- worktree if needed and open the tab.
  local function create(ref)
    local local_branch = M.local_name(ref, locals, remotes)
    local path = existing(root)[local_branch]
    if path or vim.fn.isdirectory(root .. "/.worktrees/" .. M.slug(local_branch)) == 1 then
      path = path or root .. "/.worktrees/" .. M.slug(local_branch)
      M.touch(path)
      require("config.workspace").open(path, { tab = true })
      return
    end
    path = root .. "/.worktrees/" .. M.slug(local_branch)
    git_async(
      root,
      M.add_args(ref, path, locals, remotes),
      "checking out " .. local_branch,
      function(_, add_err)
        if add_err then
          status("git worktree add: " .. add_err, vim.log.levels.ERROR)
          return
        end
        M.touch(path)
        require("config.workspace").open(path, { tab = true })
      end
    )
  end

  -- A name that matches nothing local or remote-tracking may simply not be
  -- fetched yet -- the "paste a branch name straight from GitHub" case -- so try
  -- a targeted fetch from origin before concluding it's a new branch off HEAD.
  local resolved = M.resolve(branch, locals, remote_refs(root))
  if resolved then
    return create(resolved)
  end
  if branch:find("%s") then
    return create(branch)
  end
  local short = branch:gsub("^remotes/", "")
  git_async(root, { "fetch", "origin", short }, "fetching origin/" .. short, function(ok)
    -- A failed fetch just means the name is new: fall through to -b.
    create(ok and M.resolve(branch, locals, remote_refs(root)) or branch)
  end)
end

--- Fork the current workspace tab (<leader>tf): create a NEW branch off THIS
--- worktree's HEAD, carry the uncommitted changes over (the original keeps them
--- too), open the new worktree as its own tab, and re-create every Claude Code
--- session running in this tab's side terminals -- each forked with its full
--- conversation history (`claude --resume <id> --fork-session`) into the SAME
--- fishmonger slot, so "claude 2" stays claude 2 across the fork.
---
--- The fork command is typed into a fresh shell (chansend) rather than run as
--- the terminal's job: the command is visible in the scrollback, and when the
--- forked claude exits a plain shell remains.
---
--- Carried state, deliberately narrow (first pass): tracked modifications via
--- `git stash create` + `stash apply` in the new worktree (stash create leaves
--- the source tree untouched), untracked non-ignored files by copying. Staged
--- hunks arrive unstaged; open editor buffers and plain shells do not travel.
function M.fork()
  local cwd = vim.fn.getcwd()
  local root, err = M.root(cwd)
  if not root then
    vim.notify(err or "not a git repository", vim.log.levels.ERROR)
    return
  end

  -- Collect this tab's Claude sessions BEFORE any tab switch: fishmonger's
  -- tabs() answers for the current tabpage.
  local sessions = {}
  for _, t in ipairs(require("fishmonger").tabs()) do
    if t.agent and t.agent.session then
      sessions[#sessions + 1] = { slot = t.slot, session = t.agent.session }
    end
  end

  local suggestion =
    M.fork_name(git(cwd, { "rev-parse", "--abbrev-ref", "HEAD" }), local_branches(root))
  vim.ui.input({ prompt = "Fork to new branch: ", default = suggestion }, function(input)
    local branch = vim.trim(input or "")
    if branch == "" then
      return
    end

    local base = git(cwd, { "rev-parse", "HEAD" })
    if not base then
      vim.notify("git rev-parse HEAD failed", vim.log.levels.ERROR)
      return
    end
    -- Snapshot dirty state before creating the worktree; stash create returns
    -- nothing when the tree is clean.
    local stash = git(cwd, { "stash", "create", "fork to " .. branch }) or ""
    local untracked = git(cwd, { "ls-files", "--others", "--exclude-standard" }) or ""

    local path = root .. "/.worktrees/" .. M.slug(branch)
    git_async(root, M.fork_args(branch, path, base), "forking to " .. branch, function(_, add_err)
      if add_err then
        status("git worktree add: " .. add_err, vim.log.levels.ERROR)
        return
      end

      if stash ~= "" then
        -- `stash apply` accepts any stash-shaped commit, stored or not.
        local _, apply_err = git(path, { "stash", "apply", stash })
        if apply_err then
          vim.notify(
            "carrying changes failed (worktree is clean): " .. apply_err,
            vim.log.levels.WARN
          )
        end
      end
      for file in vim.gsplit(untracked, "\n") do
        if file ~= "" then
          local dest = path .. "/" .. file
          vim.fn.mkdir(vim.fs.dirname(dest), "p")
          vim.uv.fs_copyfile(cwd .. "/" .. file, dest)
        end
      end

      require("config.workspace").open(path, { tab = true })

      -- Now in the new tab: give each session its old slot back. show() spawns
      -- the shell synchronously, so the fork command can be sent right away; the
      -- pty buffers it until the shell reads.
      local fm = require("fishmonger")
      for _, s in ipairs(sessions) do
        fm.show(s.slot, { insert = false })
        local buf = fm.slots[s.slot] and fm.slots[s.slot].buf
        local chan = buf and vim.b[buf].terminal_job_id
        if chan then
          vim.api.nvim_chan_send(chan, M.fork_cmd(s.session) .. "\n")
        end
      end
      if #sessions > 1 then
        fm.show(sessions[1].slot, { insert = false })
      end
    end)
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

---@return table<string, integer>
local function recent_load()
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
  local recent = recent_load()
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

--- <leader>tw: pick a branch, get its worktree as a tab. Recently opened
--- worktrees float to the top (see M.order); typing a name that matches nothing
--- creates a new branch off HEAD.
function M.pick()
  local cwd = vim.fn.getcwd()
  local root, err = M.root(cwd)
  if not root then
    vim.notify(err or "not a git repository", vim.log.levels.ERROR)
    return
  end
  local items = M.order(candidates(root), recent_load())
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
    -- Unlike every other picker, open in normal mode: the usual flow here is
    -- "copy a branch name from a PR/ticket, <leader>tw, p". Snacks enters
    -- insert on the input window's BufEnter, which fires in the same tick as
    -- on_show, so the stopinsert has to be scheduled to land after it.
    on_show = function()
      vim.schedule(vim.cmd.stopinsert)
    end,
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
