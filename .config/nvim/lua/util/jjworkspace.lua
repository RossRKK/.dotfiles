-- jj workspaces as workspace tabs: the jj half of <leader>tw / <leader>tf.
--
-- util/worktree.lua does this with git worktrees; jj doesn't understand those,
-- and `jj workspace` is the native equivalent. util/vcs.lua dispatches between
-- the two on `.jj`, the same way it already picks jjui over lazygit.
--
-- Deliberately parallel to worktree.lua -- same recency ordering, same picker
-- shape -- and it reuses that module for the parts that aren't about git at all.
--
-- It does NOT share the `.worktrees/<slug>` layout, and that is the one place
-- the two must differ. A git worktree gets a `.git` file, so git commands run
-- inside it resolve to that worktree. A secondary jj workspace can never have
-- one -- `jj git colocation enable` refuses outside the main workspace -- so
-- every git tool run inside a jj workspace walks UP to the enclosing repo. Put
-- the workspace under `<repo>/.worktrees/` and the consequences are: neo-tree
-- paints every file as ignored (it matches the global `.worktrees/` rule),
-- gitsigns diffs against the PARENT repo's HEAD, and triage's overview
-- describes the parent's branch. Keeping workspaces outside any repo means git
-- finds nothing rather than finding the wrong thing.
--
-- Three things collapse compared to the git side:
--   * No local-vs-remote branch resolution. jj bookmarks are one namespace, so
--     resolve/local_name/add_args have no jj counterpart -- `-r <bookmark>` is
--     the whole of it.
--   * No fetch-before-create guess. An unknown name is simply a new bookmark.
--   * No stash dance when forking. `jj workspace add -r @` parents the new
--     working copy on the current change, so uncommitted work is inherited by
--     construction and the original keeps it too -- which is what worktree.lua
--     spends a `stash create` + `stash apply` + untracked-file copy achieving.

local M = {}

local worktree = require("util.worktree")

--- Errors go through vim.notify so they land in the notifier's history, under
--- the same title the git side uses -- from the user's side this is one feature.
---@param msg string
---@param level integer
local function status(msg, level)
  vim.notify(msg, level, { title = "worktree" })
end

--- Run jj in `dir` and return trimmed stdout, or nil plus stderr on failure.
--- `--ignore-working-copy` is NOT passed: these calls either mutate the repo or
--- need an up-to-date snapshot. The read-only name query that does want it lives
--- in util/jj.lua.
---@param dir string
---@param args string[]
---@return string? out, string? err
local function jj(dir, args)
  local out = vim
    .system(vim.list_extend({ "jj", "--color=never", "--no-pager" }, args), { cwd = dir, text = true })
    :wait()
  if out.code ~= 0 then
    return nil, vim.trim(out.stderr or "")
  end
  return vim.trim(out.stdout or "")
end

--- The jj repo root containing `dir`, or nil plus a message.
---@param dir string
---@return string? root, string? err
function M.root(dir)
  local root = vim.fs.root(dir, ".jj")
  if not root then
    return nil, "not a jj repository"
  end
  return root
end

--- Where a workspace for `name` lives: a sibling of the repo, never inside it
--- (see the note at the top of this file). Grouped by repo directory name, which
--- cannot collide because two repos can't share a basename in one parent.
---
--- The workspace is NAMED for the slug too -- `jj workspace list` gives no path,
--- so the name is what lets us find the directory again.
---@param root string
---@param name string bookmark or new name
---@return string
function M.path(root, name)
  local parent = vim.fs.dirname(root)
  local repo = vim.fs.basename(root)
  return table.concat({ parent, ".jj-workspaces", repo, worktree.slug(name) }, "/")
end

--- Create the workspace at `path`, parented on `rev`.
---
--- The mkdir is not optional: `jj workspace add` refuses a destination whose
--- parent doesn't exist ("Cannot access ...: No such file or directory"), unlike
--- `git worktree add`, which creates it. The FIRST workspace in a repo is
--- therefore the one that fails, which is every repo exactly once.
---@param root string
---@param name string
---@param path string
---@param rev string
---@return string? err
function M.add(root, name, path, rev)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local _, err = jj(root, M.add_args(name, path, rev))
  return err
end

--- `jj workspace add` arguments for putting a workspace for `name` at `path`,
--- with its working copy parented on `rev`.
---@param name string
---@param path string
---@param rev string revision the new working copy sits on top of
---@return string[]
function M.add_args(name, path, rev)
  return { "workspace", "add", "--name", worktree.slug(name), "-r", rev, path }
end

--- Workspace names that already exist, as a set. The picker marks these, and
--- open() reuses them rather than trying to add a second workspace by the same
--- name (which jj rejects).
---@param root string
---@return table<string, true>
function M.workspaces(root)
  local set = {}
  local out = jj(root, { "workspace", "list", "--ignore-working-copy", "-T", 'name ++ "\n"' })
  for line in vim.gsplit(out or "", "\n") do
    if line ~= "" then
      set[line] = true
    end
  end
  return set
end

local CANDIDATE_TEMPLATE = table.concat({
  "name",
  'if(remote,remote,"")',
  "normal_target.change_id().shortest(8)",
  'normal_target.committer().timestamp().format("%s")',
  "normal_target.description().first_line()",
}, ' ++ "\t" ++ ') .. ' ++ "\n"'

--- Every bookmark, local and remote, shaped like worktree.Candidate so the
--- shared ordering and the snacks git_branch formatter both apply unchanged.
---
--- The `git` remote is dropped: in a colocated repo every bookmark is mirrored
--- there, and it is the same bookmark listed twice.
---@param root string
---@return worktree.Candidate[]
function M.candidates(root)
  local out = jj(root, {
    "bookmark",
    "list",
    "--all-remotes",
    "--ignore-working-copy",
    "-T",
    CANDIDATE_TEMPLATE,
  })
  return M.parse_candidates(out or "", M.workspaces(root), root)
end

--- The parsing half of candidates(), split out to be testable without a repo.
---@param out string `jj bookmark list` output in CANDIDATE_TEMPLATE's shape
---@param spaces table<string, true> existing workspace names
---@param root string
---@return worktree.Candidate[]
function M.parse_candidates(out, spaces, root)
  local items = {}
  for line in vim.gsplit(out, "\n") do
    -- The message separator is optional: jj()'s vim.trim strips trailing
    -- whitespace, so the LAST line of a listing whose final field (the
    -- description) is empty arrives one tab short. Requiring it dropped such a
    -- bookmark from the picker entirely, and silently.
    local name, remote, commit, time, msg =
      line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t(%d*)\t?(.*)$")
    if name and name ~= "" and remote ~= "git" then
      items[#items + 1] = {
        branch = remote ~= "" and (remote .. "/" .. name) or name,
        remote = remote ~= "",
        commit = commit,
        time = tonumber(time) or 0,
        msg = msg,
        worktree = spaces[worktree.slug(name)] and M.path(root, name) or nil,
      }
    end
  end
  return items
end

--- Open `name`'s workspace as a workspace tab, creating it if needed.
---
--- `name` may be a bookmark (possibly remote-qualified, `origin/x`, as the
--- picker offers) or a name that doesn't exist yet, in which case the workspace
--- is created and a bookmark of that name put on its working copy -- so the tab
--- has something to be called and `jj git push` has something to push.
---@param name string
---@param dir? string a directory inside the repo (default: the tab's cwd)
function M.open(name, dir)
  name = vim.trim(name)
  if name == "" then
    return
  end
  dir = dir or vim.fn.getcwd()

  local root, err = M.root(dir)
  if not root then
    status(err or "not a jj repository", vim.log.levels.ERROR)
    return
  end

  -- A remote bookmark is opened under its bare name: `origin/x` and `x` are the
  -- same line of work, and the local name is what the workspace should be
  -- called. jj resolves the bare name to the remote bookmark on its own.
  local local_name = name
  local bare = name:match("^[^/]+/(.+)$")
  if bare and M.exists(root, bare) then
    local_name = bare
  end

  local path = M.path(root, local_name)
  if M.workspaces(root)[worktree.slug(local_name)] or vim.fn.isdirectory(path) == 1 then
    worktree.touch(path)
    require("config.workspace").open(path, { tab = true })
    return
  end

  -- An existing bookmark is what the new working copy sits on; anything else is
  -- a new line of work off the current change.
  local known = M.exists(root, local_name)
  local add_err = M.add(root, local_name, path, known and local_name or "@")
  if add_err then
    status("jj workspace add: " .. add_err, vim.log.levels.ERROR)
    return
  end
  if not known then
    local _, mark_err = jj(path, { "bookmark", "create", local_name, "-r", "@" })
    if mark_err then
      -- The workspace is real and usable; only its name is missing.
      status("bookmark " .. local_name .. ": " .. mark_err, vim.log.levels.WARN)
    end
  end
  worktree.touch(path)
  require("config.workspace").open(path, { tab = true })
end

--- Is `name` a bookmark this repo knows (local, or on any remote)?
---@param root string
---@param name string
---@return boolean
function M.exists(root, name)
  local out = jj(root, {
    "log",
    "--no-graph",
    "--ignore-working-copy",
    "-r",
    "present(bookmarks(exact:" .. vim.json.encode(name) .. "))",
    "-T",
    '"x"',
  })
  return out ~= nil and out ~= ""
end

--- Fork the current workspace tab (<leader>tf): a new workspace whose working
--- copy is parented on THIS one's current change, so the uncommitted work comes
--- with it and the original keeps it too. Then re-create every Claude Code
--- session running in this tab's side terminals, each forked with its full
--- history into the SAME fishmonger slot -- identical to the git side, and the
--- reason that half is shared rather than reimplemented.
function M.fork()
  local cwd = vim.fn.getcwd()
  local root, err = M.root(cwd)
  if not root then
    status(err or "not a jj repository", vim.log.levels.ERROR)
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

  -- The greeter's cached report names the current change (triage answers it per
  -- VCS now); package.loaded, not require, for the same reason display_name
  -- does it -- before its setup there is no report to read anyway.
  local greeter = package.loaded["config.greeter"]
  local report = greeter and greeter.reports[vim.fs.normalize(cwd)]
  local names = {}
  for _, it in ipairs(M.candidates(root)) do
    names[it.branch] = true
  end
  local suggestion = worktree.fork_name(report and report.branch, names)

  vim.ui.input({ prompt = "Fork to new bookmark: ", default = suggestion }, function(input)
    local name = vim.trim(input or "")
    if name == "" then
      return
    end
    local path = M.path(root, name)
    -- -r @ (not @-): the fork starts on top of the current change, which is
    -- where the uncommitted work lives.
    local add_err = M.add(cwd, name, path, "@")
    if add_err then
      status("jj workspace add: " .. add_err, vim.log.levels.ERROR)
      return
    end
    local _, mark_err = jj(path, { "bookmark", "create", name, "-r", "@" })
    if mark_err then
      status("bookmark " .. name .. ": " .. mark_err, vim.log.levels.WARN)
    end
    worktree.touch(path)
    require("config.workspace").open(path, { tab = true })

    worktree.restore_sessions(sessions)
  end)
end

--- M.open, callable from a jjui custom action over `nvim --remote-expr`, the way
--- util/worktree.lua's open_from_lazygit is called from lazygit. The float has
--- to hide first (the new tab would otherwise be built underneath it), and the
--- real work is deferred so the RPC reply returns immediately.
---@param name string bookmark name
---@return string '' -- --remote-expr prints the expression's value; keep it empty
function M.open_from_jjui(name)
  local cwd = vim.fn.getcwd()
  require("util.jjui").hide()
  vim.schedule(function()
    M.open(name, cwd)
  end)
  return ""
end

--- <leader>tw: pick a bookmark, get its workspace as a tab. Recently opened
--- workspaces float to the top (worktree.order); typing a name that matches
--- nothing creates a new one off the current change.
function M.pick()
  local cwd = vim.fn.getcwd()
  local root, err = M.root(cwd)
  if not root then
    status(err or "not a jj repository", vim.log.levels.ERROR)
    return
  end
  local items = worktree.order(M.candidates(root), worktree.recent_load())
  for i, it in ipairs(items) do
    it.text = (it.name or it.branch) .. " " .. (it.msg or "")
    it.cwd = root
    it.idx = i
  end
  Snacks.picker.pick({
    source = "worktree",
    title = "Workspaces (jj)",
    items = items,
    format = function(item, picker)
      local ret = Snacks.picker.format.git_branch(
        vim.tbl_extend("force", item, { branch = item.name or item.branch }),
        picker
      )
      table.insert(ret, 2, { item.worktree and "\u{f0e8e} " or "   ", "SnacksPickerGitBranch" })
      return ret
    end,
    -- No preview: snacks' git_log preview shells out to git, which can say
    -- nothing useful about a jj change id.
    on_show = function()
      vim.schedule(vim.cmd.stopinsert)
    end,
    confirm = function(picker, item)
      local pattern = picker:filter().pattern
      picker:close()
      local name = item and item.branch or pattern
      if name then
        M.open(name, cwd)
      end
    end,
  })
end

return M
