-- A jj backend for neo-tree's status column and gitignore dimming.
--
-- neo-tree only knows git. It keeps one entry per repo root in
-- `neo-tree.git.worktrees[root].status`: a map of absolute path to a status
-- code ("!" ignored, "?" untracked, or a two-char index/worktree code such as
-- ".M"). The `git_status` column reads that map through the LONGEST matching
-- root, and the filesystem scan dims a node whose code resolves to "!". When a
-- root has an entry but no status, the scan falls back to `git check-ignore`.
--
-- In a secondary jj workspace there is no `.git`, so git resolves UP to the
-- main workspace, where the global `.worktrees/` ignore rule paints every file
-- ignored. Rather than switch git off, this module fills in the same map from
-- jj and registers the jj root as a worktree entry. Being the longest root, it
-- shadows the parent's entry for everything under it.
--
-- Codes:
--   * changes come from `jj diff --summary -r @`, i.e. the working copy against
--     its parent -- the same thing `git status` shows in a colocated repo, where
--     jj keeps HEAD on `@-`. They are stored as ".M"/".A"/".D"/".R" (worktree
--     column set, index column empty: jj has no index) and bubbled to parents.
--   * ignored is the complement of `jj file list`. jj auto-tracks every file
--     that is not ignored, so an on-disk path jj does not list is ignored, and
--     a directory with no listed file under it is ignored. The rare exceptions
--     -- a file excluded by `snapshot.auto-track`, or one over the size limit
--     -- show as ignored too, which is accepted.
--
-- The pure parts (parsing, bubbling, the ignored decision) take strings and
-- lists so the spec can drive them without a repo.

local M = {}

--- Map `jj diff --summary` status letters onto neo-tree's two-char codes.
local CODE = { M = ".M", A = ".A", D = ".D", R = ".R", C = ".C" }

--- Parent directory of an absolute path, nil at "/".
---@param path string
---@return string?
local function parent_of(path)
  local p = path:match("^(.*)/[^/]+$")
  if p == nil or p == "" then
    return nil
  end
  return p
end

--- Parse `jj diff --summary` output into a path -> code map, bubbling each
--- code to parent directories up to (excluding) `root`. The first code to
--- reach a parent wins, in the order jj printed them -- good enough for a
--- glyph.
---@param out string
---@param root string absolute jj root, no trailing slash
---@return table<string, string>
function M.parse_summary(out, root)
  local status = {}
  for line in vim.gsplit(out, "\n", { plain = true, trimempty = true }) do
    local letter, rest = line:match("^(%u) (.+)$")
    if letter and CODE[letter] then
      -- "R old => new": the new path is the one on disk.
      local new = rest:match("=> (.+)$") or rest
      local abs = root .. "/" .. new
      status[abs] = CODE[letter]
      local p = parent_of(abs)
      while p and #p > #root and status[p] == nil do
        status[p] = CODE[letter]
        p = parent_of(p)
      end
    end
  end
  return status
end

--- Build the set of tracked files and every directory that holds one, from
--- `jj file list` output (one repo-relative path per line).
---@param out string
---@param root string
---@return table<string, true> tracked absolute paths of files and their directories
function M.tracked_set(out, root)
  local set = {}
  for line in vim.gsplit(out, "\n", { plain = true, trimempty = true }) do
    local abs = root .. "/" .. line
    set[abs] = true
    local p = parent_of(abs)
    while p and #p > #root and not set[p] do
      set[p] = true
      p = parent_of(p)
    end
  end
  return set
end

--- Mark every path in `paths` that is not tracked as ignored ("!") in `status`.
--- `paths` are the nodes neo-tree currently shows; the tracked set covers the
--- whole repo, so this stays correct however deep the tree is expanded. The
--- `.jj` directory itself counts as ignored, like `.git` does for git.
---@param status table<string, string>
---@param tracked table<string, true>
---@param paths string[]
---@param root string
---@return table<string, string> status (the same table, for chaining)
function M.mark_ignored(status, tracked, paths, root)
  for _, path in ipairs(paths) do
    if path ~= root and not tracked[path] and status[path] == nil then
      status[path] = "!"
    end
  end
  return status
end

--- Run jj in `root` and return trimmed stdout, or nil plus stderr.
---@param root string
---@param args string[]
---@param snapshot boolean
---@return string?, string?
local function jj(root, args, snapshot)
  local cmd = { "jj", "--color=never", "--no-pager" }
  if not snapshot then
    table.insert(cmd, "--ignore-working-copy")
  end
  vim.list_extend(cmd, args)
  local out = vim.system(cmd, { cwd = root, text = true }):wait()
  if out.code ~= 0 then
    return nil, vim.trim(out.stderr or "")
  end
  return out.stdout or ""
end

--- Per-root cache: the last summary and tracked set, and when jj was asked.
---@type table<string, {at: number, summary: string, files: string}>
local cache = {}

--- Minimum gap between two jj runs for one root, in ms. A snapshot walks the
--- working copy, so renders in quick succession share one.
M.debounce_ms = 1000

--- Query jj for `root`, honouring the debounce. The first call for a root
--- snapshots so a fresh workspace shows its files; later calls within the
--- window reuse the previous answer.
---@param root string
---@return string? summary, string? files, string? err
local function query(root)
  local now = vim.uv.now()
  local c = cache[root]
  if c and now - c.at < M.debounce_ms then
    return c.summary, c.files
  end
  local summary, err = jj(root, { "diff", "--summary", "-r", "@" }, true)
  if not summary then
    return nil, nil, err
  end
  -- The snapshot above already refreshed the working copy; no second walk.
  local files, ferr = jj(root, { "file", "list" }, false)
  if not files then
    return nil, nil, ferr
  end
  cache[root] = { at = now, summary = summary, files = files }
  return summary, files
end

--- The jj root containing `path`, or nil.
---@param path string
---@return string?
function M.root(path)
  return vim.fs.root(path, ".jj")
end

--- Refresh neo-tree's worktree entry for the jj root of `root` so that `paths`
--- (the nodes about to be drawn) get jj's codes. Returns false, err on failure
--- so the caller can leave git in charge.
---@param root string
---@param paths string[]
---@return boolean ok, string? err
function M.refresh(root, paths)
  local summary, files, err = query(root)
  if not summary or not files then
    return false, err
  end
  local status = M.parse_summary(summary, root)
  M.mark_ignored(status, M.tracked_set(files, root), paths, root)

  local git = require("neo-tree.git")
  local entry = git.worktrees[root]
  if not entry then
    entry = { git_dir = root .. "/.jj", status_diff = {} }
    git.worktrees[root] = entry
    -- neo-tree caches "which root owns this path" weakly; a new root
    -- invalidates it, the same way its own registration does.
    git._upward_worktree_cache = setmetatable({}, { __mode = "kv" })
  end
  entry.status = status
  return true
end

--- Every path in a neo-tree state's tree, so ignored marks cover what is shown.
---@param state table neotree.State
---@return string[]
function M.tree_paths(state)
  local paths = {}
  if not state.tree then
    return paths
  end
  local function walk(node)
    paths[#paths + 1] = node.path
    if node:has_children() then
      for _, id in ipairs(node:get_child_ids()) do
        local child = state.tree:get_node(id)
        if child then
          walk(child)
        end
      end
    end
  end
  for _, node in ipairs(state.tree:get_nodes()) do
    walk(node)
  end
  return paths
end

--- neo-tree BEFORE_RENDER handler: in a jj repo, take over the status map for
--- this state and switch off its git fallback (the scan's `check-ignore` path
--- and its own status refresh). Outside a jj repo, or if jj fails, do nothing
--- and git carries on as before.
---@param state table neotree.State
function M.before_render(state)
  if not state or not state.path then
    return
  end
  local root = M.root(state.path)
  if not root then
    if state.enable_git_status == false and state.jjstatus_owned then
      state.enable_git_status = nil
      state.jjstatus_owned = nil
    end
    return
  end
  local ok, err = M.refresh(root, M.tree_paths(state))
  if not ok then
    vim.notify_once("jjstatus: " .. tostring(err), vim.log.levels.WARN, { title = "neo-tree" })
    return
  end
  state.enable_git_status = false
  state.jjstatus_owned = true
end

--- Forget cached jj answers, e.g. after a jj command ran elsewhere.
---@param root string? one root, or all
function M.invalidate(root)
  if root then
    cache[root] = nil
  else
    cache = {}
  end
end

return M
