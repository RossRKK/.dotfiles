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
    return { "worktree", "add", "--track", "-b", rest, path, branch }
  end
  return { "worktree", "add", "-b", branch, path }
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

  local short = branch:gsub("^remotes/", "")
  local path = existing(root)[short]
  if not path then
    path = root .. "/.worktrees/" .. M.slug(branch)
    if vim.fn.isdirectory(path) ~= 1 then
      local _, add_err =
        git(root, M.add_args(branch, path, local_branches(root), remote_names(root)))
      if add_err then
        vim.notify("git worktree add: " .. add_err, vim.log.levels.ERROR)
        return
      end
    end
  end

  require("config.workspace").open(path, { tab = true })
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
