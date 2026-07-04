-- Branch "review mode".
--
-- Treats the branch as a review unit: "under review" is what merging this branch
-- into the default branch would actually change (the merge-result diff), so a
-- change the default branch already has — even one the branch made independently
-- — is not flagged. Two surfaces consume this:
--   * gitsigns, based on the default-branch tip so its sign-column marks show the
--     lines that differ from what's already there (see lua/plugins/git.lua).
--   * a custom nvim-tree decorator that colours changed files in the explorer
--     (see lua/review/decorator.lua).
--
-- The file list combines the merge-result diff (committed branch work) with your
-- uncommitted changes and untracked files, so you can review before committing.
--
-- Files can be marked "reviewed", which records the file's current blob hash.
-- A reviewed file flips back to "changed" automatically if it's edited again
-- (its hash no longer matches), so you re-review real changes.

local M = {}

-- Absolute path -> "changed" | "reviewed", rebuilt on every refresh().
M.status_by_path = {}

-- Directory absolute path -> rolled-up status of its descendants:
--   "changed"  at least one descendant is changed-and-unreviewed
--   "reviewed" descendants are all reviewed (and there's at least one)
M.folder_status = {}

-- Whether review mode is currently active (a git repo with a usable merge-base).
M.active = false

-- Toggle: when false, gitsigns stays on its normal HEAD base and the explorer
-- decorator is dormant. Defaults on ("review mode all the time").
M.enabled = true

local uv = vim.uv or vim.loop

--- Run git in `root` and return stdout lines (empty table on failure).
---@param root string
---@param args string[]
---@return string[]
local function git(root, args)
  local cmd = { "git", "-C", root }
  vim.list_extend(cmd, args)
  local out = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    return {}
  end
  return out
end

--- Toplevel of the repo containing cwd, or nil if not in a work tree.
---@return string?
local function repo_root()
  local out = vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })
  if vim.v.shell_error ~= 0 or not out[1] or out[1] == "" then
    return nil
  end
  return out[1]
end

--- Best guess at the branch we're reviewing against.
---@param root string
---@return string?
local function default_branch(root)
  -- Prefer the remote's advertised default (origin/HEAD -> origin/main|master).
  local head = git(root, { "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD" })[1]
  if head and head ~= "" then
    return head
  end
  for _, candidate in ipairs({ "origin/main", "origin/master", "main", "master" }) do
    if #git(root, { "rev-parse", "--verify", "--quiet", candidate }) > 0 then
      return candidate
    end
  end
  return nil
end

--- The tree that would result from merging HEAD into the default branch — i.e.
--- the content of the merge commit you'd get by merging this branch. Returns the
--- tree object id, or nil.
---
--- This is the "what the merge actually applies" view: a file the branch changed
--- to content the default branch already reached contributes nothing, and a file
--- only the default branch changed is taken from there, so neither shows up as a
--- branch change. (Contrast the three-dot merge-base diff GitHub renders, which
--- would still show the former.)
---@param root string
---@param branch string default-branch ref
---@return string?
local function merged_tree(root, branch)
  -- `--write-tree` writes the merged tree and prints its oid on the first line.
  -- On a conflicted merge git exits non-zero but still prints the tree oid first,
  -- so read output directly rather than going through git() (which drops it).
  local out = vim.fn.systemlist({ "git", "-C", root, "merge-tree", "--write-tree", branch, "HEAD" })
  local tree = out[1]
  if not tree or not tree:match("^%x%x%x%x%x%x%x") then
    return nil
  end
  return tree
end

-- ---------------------------------------------------------------------------
-- Reviewed-set persistence (per repo, under stdpath("state")/review/).
-- File format: one "<blob-hash> <relative/path>" per line.
-- ---------------------------------------------------------------------------

local function state_dir()
  local dir = vim.fn.stdpath("state") .. "/review"
  vim.fn.mkdir(dir, "p")
  return dir
end

---@param root string
---@return string
local function reviewed_file(root)
  -- Sanitise the repo path into a single filename component.
  local key = root:gsub("[/\\:]", "%%")
  return state_dir() .. "/" .. key
end

--- Load reviewed set: relative path -> blob hash recorded at review time.
---@param root string
---@return table<string, string>
local function load_reviewed(root)
  local reviewed = {}
  local path = reviewed_file(root)
  if vim.fn.filereadable(path) == 0 then
    return reviewed
  end
  for _, line in ipairs(vim.fn.readfile(path)) do
    local hash, rel = line:match("^(%S+)%s+(.+)$")
    if hash and rel then
      reviewed[rel] = hash
    end
  end
  return reviewed
end

---@param root string
---@param reviewed table<string, string>
local function save_reviewed(root, reviewed)
  local lines = {}
  for rel, hash in pairs(reviewed) do
    table.insert(lines, hash .. " " .. rel)
  end
  table.sort(lines)
  vim.fn.writefile(lines, reviewed_file(root))
end

--- Current blob hash of a working-tree file, or nil.
---@param root string
---@param rel string
---@return string?
local function blob_hash(root, rel)
  local hash = git(root, { "hash-object", "--", rel })[1]
  if not hash or hash == "" then
    return nil
  end
  return hash
end

--- Resolve a ref to its commit sha (cheap; used for cache keys).
---@param root string
---@param ref string
---@return string?
local function rev(root, ref)
  local sha = git(root, { "rev-parse", "--verify", "--quiet", ref })[1]
  return (sha and sha ~= "") and sha or nil
end

-- Cache of the expensive merge-result step, keyed by the two commits it depends
-- on. The merge tree — and therefore the set of files the merge changes — only
-- moves when HEAD or the base branch moves, so on a focus/save where neither
-- changed we skip `git merge-tree` (seconds on a big monorepo) entirely.
---@type { root: string, base: string, head: string, files: table<string, boolean> }?
local merge_cache = nil

--- Files the merge of HEAD into `branch` would change vs the branch tip, as a
--- rel-path set. Memoised on (root, base sha, head sha).
---@param root string
---@param branch string
---@param base_sha string
---@param head_sha string
---@return table<string, boolean>?
local function committed_changed(root, branch, base_sha, head_sha)
  if
    merge_cache
    and merge_cache.root == root
    and merge_cache.base == base_sha
    and merge_cache.head == head_sha
  then
    return merge_cache.files
  end

  local tree = merged_tree(root, branch)
  if not tree then
    return nil
  end
  local files = {}
  for _, rel in ipairs(git(root, { "diff", "--name-only", "--diff-filter=d", branch, tree })) do
    files[rel] = true
  end
  merge_cache = { root = root, base = base_sha, head = head_sha, files = files }
  return files
end

-- ---------------------------------------------------------------------------

--- Rebuild status_by_path from git and reapply the gitsigns base.
--- The expensive merge step is cached on commit shas (see committed_changed),
--- so the common focus/save path is just a couple of cheap diffs.
function M.refresh()
  M.status_by_path = {}
  M.folder_status = {}
  M.active = false

  if not M.enabled then
    require("review.gitsigns").set_base(nil)
    M.redraw_tree()
    return
  end

  local root = repo_root()
  if not root then
    require("review.gitsigns").set_base(nil)
    M.redraw_tree()
    return
  end

  local branch = default_branch(root)
  local base_sha = branch and rev(root, branch)
  local head_sha = rev(root, "HEAD")
  -- Files the merge would actually change vs the default branch. This is the
  -- merge-result diff, so files the branch changed to content the default branch
  -- already has don't appear. Cached on the two shas, so it's free when neither
  -- HEAD nor the base has moved since the last refresh.
  local committed = branch and base_sha and head_sha
    and committed_changed(root, branch, base_sha, head_sha)
  if not branch or not committed then
    require("review.gitsigns").set_base(nil)
    M.redraw_tree()
    return
  end

  M.active = true
  -- Per-line signs: diff the buffer against the default-branch tip, so a line
  -- that matches what's already on the branch shows no sign — consistent with
  -- the merge-result file list below.
  require("review.gitsigns").set_base(branch)

  local changed = {} -- rel path -> true (dedup)
  for rel in pairs(committed) do
    changed[rel] = true
  end
  -- Also include uncommitted work (staged + unstaged edits, and untracked
  -- files) so you can review changes before committing them. These are the
  -- cheaper git calls and change on save, so they're recomputed every time.
  for _, rel in ipairs(git(root, { "diff", "--name-only", "--diff-filter=d", "HEAD" })) do
    changed[rel] = true
  end
  for _, rel in ipairs(git(root, { "ls-files", "--others", "--exclude-standard" })) do
    changed[rel] = true
  end

  local reviewed = load_reviewed(root)
  local still_changed = {} -- prune reviewed entries no longer in the diff

  for rel in pairs(changed) do
    local abs = vim.fs.normalize(root .. "/" .. rel)
    local recorded = reviewed[rel]
    if recorded and recorded == blob_hash(root, rel) then
      M.status_by_path[abs] = "reviewed"
      still_changed[rel] = recorded
    else
      -- New change, or a reviewed file that was edited again: needs review.
      M.status_by_path[abs] = "changed"
    end
  end

  -- Drop reviewed records for files that no longer differ (e.g. after a rebase).
  if next(reviewed) then
    save_reviewed(root, still_changed)
  end

  -- Roll each file's status up to its ancestor directories. "changed" dominates:
  -- a folder is only "reviewed" once every changed descendant is reviewed.
  local nroot = vim.fs.normalize(root)
  for abs, st in pairs(M.status_by_path) do
    local dir = vim.fs.dirname(abs)
    while dir and #dir >= #nroot and (dir == nroot or dir:sub(1, #nroot + 1) == nroot .. "/") do
      if M.folder_status[dir] ~= "changed" then
        M.folder_status[dir] = (st == "changed") and "changed" or "reviewed"
      end
      if dir == nroot then
        break
      end
      dir = vim.fs.dirname(dir)
    end
  end

  M.redraw_tree()
end

--- Status for an absolute path: "changed" | "reviewed" | nil.
---@param abs string?
---@return string?
function M.status(abs)
  if not abs then
    return nil
  end
  return M.status_by_path[vim.fs.normalize(abs)]
end

--- Rolled-up status for a directory: "changed" | "reviewed" | nil.
---@param abs string?
---@return string?
function M.folder(abs)
  if not abs then
    return nil
  end
  return M.folder_status[vim.fs.normalize(abs)]
end

--- The path the review action should act on: the node under the cursor when in
--- the explorer, otherwise the current buffer's file. nil if neither applies.
---@return string?
local function target_path()
  if vim.bo.filetype == "NvimTree" then
    local ok, api = pcall(require, "nvim-tree.api")
    if ok then
      local node = api.tree.get_node_under_cursor()
      if node and node.absolute_path then
        return node.absolute_path
      end
    end
    return nil
  end
  local name = vim.api.nvim_buf_get_name(0)
  return name ~= "" and name or nil
end

--- Set the reviewed state of a file or directory (recursively).
--- Defaults to the explorer node under the cursor / current buffer.
---@param reviewed boolean true = mark reviewed, false = mark not reviewed
---@param abs string? target path
function M.mark(reviewed, abs)
  abs = abs or target_path()
  if not abs or abs == "" then
    return
  end
  abs = vim.fs.normalize(abs)

  local root = repo_root()
  if not root then
    vim.notify("review: not in a git repo", vim.log.levels.WARN)
    return
  end
  local nroot = vim.fs.normalize(root)

  -- Collect the changed files this action covers. For a directory, that's every
  -- changed descendant; for a file, just itself (if it's actually changed).
  local targets = {}
  if vim.fn.isdirectory(abs) == 1 then
    for path in pairs(M.status_by_path) do
      if path == abs or path:sub(1, #abs + 1) == abs .. "/" then
        table.insert(targets, path)
      end
    end
  elseif M.status_by_path[abs] then
    table.insert(targets, abs)
  end

  if #targets == 0 then
    vim.notify("review: nothing changed here to mark", vim.log.levels.INFO)
    return
  end

  local reviewed_map = load_reviewed(root)
  for _, path in ipairs(targets) do
    local rel = path:sub(#nroot + 2)
    if reviewed then
      local hash = blob_hash(root, rel)
      if hash then
        reviewed_map[rel] = hash
      end
    else
      reviewed_map[rel] = nil
    end
  end
  save_reviewed(root, reviewed_map)

  vim.notify(("review: marked %d file(s) %s"):format(#targets, reviewed and "reviewed" or "not reviewed"))
  M.refresh()
end

--- Turn review mode on/off (gitsigns base + explorer colours).
function M.toggle()
  M.enabled = not M.enabled
  vim.notify("review mode " .. (M.enabled and "on" or "off"))
  M.refresh()
end

--- Re-render the explorer so the decorator picks up new status.
function M.redraw_tree()
  local ok, api = pcall(require, "nvim-tree.api")
  if ok and api.tree.is_visible() then
    api.tree.reload()
  end
end

function M.setup()
  -- Themeable highlight groups for the explorer indicators.
  local function set_hl()
    vim.api.nvim_set_hl(0, "ReviewChanged", { link = "DiagnosticWarn", default = true })
    vim.api.nvim_set_hl(0, "ReviewReviewed", { link = "DiagnosticOk", default = true })
  end
  vim.api.nvim_create_autocmd("ColorScheme", { callback = set_hl })
  set_hl()

  vim.api.nvim_create_user_command("ReviewRefresh", M.refresh, { desc = "Recompute branch review status" })
  vim.api.nvim_create_user_command("ReviewToggle", M.toggle, { desc = "Toggle branch review mode" })
  vim.api.nvim_create_user_command("ReviewMark", function()
    M.mark(true)
  end, { desc = "Mark file/folder under cursor reviewed" })
  vim.api.nvim_create_user_command("ReviewUnmark", function()
    M.mark(false)
  end, { desc = "Mark file/folder under cursor not reviewed" })

  vim.keymap.set("n", "<leader>rr", function()
    M.mark(true)
  end, { desc = "Review: mark reviewed" })
  vim.keymap.set("n", "<leader>ru", function()
    M.mark(false)
  end, { desc = "Review: mark not reviewed (unreview)" })
  vim.keymap.set("n", "<leader>rt", M.toggle, { desc = "Review: toggle review mode" })
  vim.keymap.set("n", "<leader>rR", M.refresh, { desc = "Review: refresh status" })

  -- Keep status fresh without being expensive: on save, on regaining focus
  -- (branch may have moved), and once at startup.
  vim.api.nvim_create_autocmd({ "BufWritePost", "FocusGained", "DirChanged" }, {
    callback = function()
      -- Debounce a touch so a burst of events collapses into one git pass.
      if M._pending then
        M._pending:stop()
      end
      M._pending = vim.defer_fn(M.refresh, 150)
    end,
  })
  vim.defer_fn(M.refresh, 200)
end

return M
