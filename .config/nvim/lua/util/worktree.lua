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

  -- A name that matches nothing local or remote-tracking may simply not be
  -- fetched yet -- the "paste a branch name straight from GitHub" case -- so try
  -- a targeted fetch from origin before concluding it's a new branch off HEAD.
  local locals = local_branches(root)
  local resolved = M.resolve(branch, locals, remote_refs(root))
  if not resolved and not branch:find("%s") then
    local short = branch:gsub("^remotes/", "")
    if git(root, { "fetch", "origin", short }) then
      resolved = M.resolve(branch, locals, remote_refs(root))
    end
  end
  branch = resolved or branch

  local remotes = remote_names(root)
  local local_branch = M.local_name(branch, locals, remotes)
  local path = existing(root)[local_branch]
  if not path then
    path = root .. "/.worktrees/" .. M.slug(local_branch)
    if vim.fn.isdirectory(path) ~= 1 then
      local _, add_err = git(root, M.add_args(branch, path, locals, remotes))
      if add_err then
        vim.notify("git worktree add: " .. add_err, vim.log.levels.ERROR)
        return
      end
    end
  end

  require("config.workspace").open(path, { tab = true })
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

  local suggestion = M.fork_name(git(cwd, { "rev-parse", "--abbrev-ref", "HEAD" }), local_branches(root))
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
    local _, add_err = git(root, M.fork_args(branch, path, base))
    if add_err then
      vim.notify("git worktree add: " .. add_err, vim.log.levels.ERROR)
      return
    end

    if stash ~= "" then
      -- `stash apply` accepts any stash-shaped commit, stored or not.
      local _, apply_err = git(path, { "stash", "apply", stash })
      if apply_err then
        vim.notify("carrying changes failed (worktree is clean): " .. apply_err, vim.log.levels.WARN)
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
function M.pick()
  local cwd = vim.fn.getcwd()
  Snacks.picker.git_branches({
    all = true,
    cwd = cwd,
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
