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
-- decorator is dormant. Defaults off; turn on per-branch with <leader>rt.
M.enabled = false

local uv = vim.uv or vim.loop

--- Run a command asynchronously, yielding the current coroutine until it exits.
--- MUST be called from within a coroutine (refresh/mark drive one). Returns the
--- stdout lines and the exit code; stdout is returned even on a non-zero exit so
--- callers like merged_tree can read a conflicted merge's tree oid.
---@param cmd string[]
---@return string[] lines, integer code
local function sh(cmd)
  local co = assert(coroutine.running(), "review: git must run inside a coroutine")
  vim.system(cmd, { text = true }, function(obj)
    vim.schedule(function()
      local lines = {}
      for line in (obj.stdout or ""):gmatch("[^\r\n]+") do
        lines[#lines + 1] = line
      end
      coroutine.resume(co, lines, obj.code)
    end)
  end)
  return coroutine.yield()
end

--- Run git in `root` (async).
---@param root string
---@param args string[]
---@return string[]
local function git(root, args)
  local cmd = { "git", "-C", root }
  vim.list_extend(cmd, args)
  return (sh(cmd))
end

--- Toplevel of the repo containing cwd, or nil if not in a work tree (async).
---@return string?
local function repo_root()
  local out = sh({ "git", "rev-parse", "--show-toplevel" })
  local root = out[1]
  return (root and root ~= "") and root or nil
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
  -- On a conflicted merge git exits non-zero but still prints the tree oid first;
  -- sh() keeps stdout regardless of exit code, so git() is fine here.
  local out = git(root, { "merge-tree", "--write-tree", branch, "HEAD" })
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

-- Bumped on every refresh; an in-flight async run whose generation is stale
-- (a newer refresh started) discards its results instead of clobbering state.
local refresh_gen = 0

--- Clear all review state and reset gitsigns; used by the inactive paths.
local function deactivate()
  M.status_by_path = {}
  M.folder_status = {}
  M.active = false
  require("review.gitsigns").set_base(nil)
  M.redraw_tree()
end

--- The async body of a refresh. Runs inside a coroutine; every git() call yields
--- without blocking the UI. Builds new state in locals and only commits it at the
--- end, so a partial run never leaves half-updated tables on screen.
---@param mygen integer generation this run belongs to
local function do_refresh(mygen)
  local function stale()
    return mygen ~= refresh_gen
  end

  if not M.enabled then
    return deactivate()
  end

  local root = repo_root()
  if stale() then
    return
  end
  if not root then
    return deactivate()
  end

  local branch = default_branch(root)
  local base_sha = branch and rev(root, branch)
  local head_sha = rev(root, "HEAD")
  -- Files the merge would actually change vs the default branch. This is the
  -- merge-result diff, so files the branch changed to content the default branch
  -- already has don't appear. Cached on the two shas, so it's free (no git) when
  -- neither HEAD nor the base has moved since the last refresh.
  local committed = branch and base_sha and head_sha
    and committed_changed(root, branch, base_sha, head_sha)
  if stale() then
    return
  end
  if not branch or not committed then
    return deactivate()
  end

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
  if stale() then
    return
  end

  local reviewed = load_reviewed(root)
  local status_by_path = {}
  local still_changed = {} -- prune reviewed entries no longer in the diff

  for rel in pairs(changed) do
    local abs = vim.fs.normalize(root .. "/" .. rel)
    local recorded = reviewed[rel]
    if recorded and recorded == blob_hash(root, rel) then
      status_by_path[abs] = "reviewed"
      still_changed[rel] = recorded
    else
      -- New change, or a reviewed file that was edited again: needs review.
      status_by_path[abs] = "changed"
    end
  end
  if stale() then
    return
  end

  -- Roll each file's status up to its ancestor directories. "changed" dominates:
  -- a folder is only "reviewed" once every changed descendant is reviewed.
  local folder_status = {}
  local nroot = vim.fs.normalize(root)
  for abs, st in pairs(status_by_path) do
    local dir = vim.fs.dirname(abs)
    while dir and #dir >= #nroot and (dir == nroot or dir:sub(1, #nroot + 1) == nroot .. "/") do
      if folder_status[dir] ~= "changed" then
        folder_status[dir] = (st == "changed") and "changed" or "reviewed"
      end
      if dir == nroot then
        break
      end
      dir = vim.fs.dirname(dir)
    end
  end

  -- Commit the freshly built state atomically.
  M.status_by_path = status_by_path
  M.folder_status = folder_status
  M.active = true
  -- Drop reviewed records for files that no longer differ (e.g. after a rebase).
  if next(reviewed) then
    save_reviewed(root, still_changed)
  end
  -- Per-line signs: diff the buffer against the default-branch tip, so a line
  -- that matches what's already on the branch shows no sign — consistent with
  -- the merge-result file list above.
  require("review.gitsigns").set_base(branch)
  M.redraw_tree()
end

--- Recompute review status without blocking the UI. Returns immediately; the
--- work runs on an async coroutine and applies its results when done.
function M.refresh()
  refresh_gen = refresh_gen + 1
  local mygen = refresh_gen
  coroutine.wrap(function()
    local ok, err = pcall(do_refresh, mygen)
    if not ok then
      vim.notify("review: refresh failed: " .. tostring(err), vim.log.levels.ERROR)
    end
  end)()
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
  -- Resolve the target from cursor/buffer state up front (sync), before the
  -- async git work below can move the cursor or change the current window.
  abs = abs or target_path()
  if not abs or abs == "" then
    return
  end
  abs = vim.fs.normalize(abs)
  local is_dir = vim.fn.isdirectory(abs) == 1

  coroutine.wrap(function()
    local ok, err = pcall(function()
      local root = repo_root()
      if not root then
        vim.notify("review: not in a git repo", vim.log.levels.WARN)
        return
      end
      local nroot = vim.fs.normalize(root)

      -- Collect the changed files this action covers. For a directory, that's
      -- every changed descendant; for a file, just itself (if it's changed).
      local targets = {}
      if is_dir then
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
    end)
    if not ok then
      vim.notify("review: mark failed: " .. tostring(err), vim.log.levels.ERROR)
    end
  end)()
end

--- Turn review mode on/off (gitsigns base + explorer colours).
function M.toggle()
  M.enabled = not M.enabled
  vim.notify("review mode " .. (M.enabled and "on" or "off"))
  M.refresh()
end

--- Ref the diff view compares against: the review base if review mode set one,
--- else the default branch tip — so the diff still shows branch-level changes
--- when the sign-column review mode is off (mirrors the fallback in git.lua).
---@return string
local function diff_base()
  local base = require("review.gitsigns").current
  if base then
    return base
  end
  local default = vim.fn.systemlist({ "git", "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD" })[1]
  return (default and default ~= "") and default or "origin/main"
end

-- Combined inline diff: deleted lines rendered inline as virtual text and
-- changed lines (word-level) highlighted on the file buffer itself, against the
-- review base — rather than a side-by-side split. Global gitsigns state, so it's
-- a mode across all buffers, not per-window.
M.inline_diff = false

--- Toggle the combined inline diff. While on, point gitsigns at the review base
--- (even if the sign-column review mode is off); restore the prior base when off.
function M.toggle_diff()
  local ok, gs = pcall(require, "gitsigns")
  if not ok then
    vim.notify("review: gitsigns not available", vim.log.levels.WARN)
    return
  end
  M.inline_diff = not M.inline_diff
  local gsbase = require("review.gitsigns")
  gs.toggle_deleted(M.inline_diff)
  gs.toggle_linehl(M.inline_diff)
  gs.toggle_word_diff(M.inline_diff)
  -- set_base refreshes gitsigns, which is what renders the toggles above; do it
  -- last so enabling and disabling both repaint in one pass.
  if M.inline_diff then
    M._diff_prev_base = gsbase.current
    gsbase.set_base(diff_base())
  else
    gsbase.set_base(M._diff_prev_base)
    M._diff_prev_base = nil
  end
end

--- Re-render the explorer so the decorator picks up new status.
function M.redraw_tree()
  local ok, api = pcall(require, "nvim-tree.api")
  if ok and api.tree.is_visible() then
    api.tree.reload()
  end
end

function M.setup()
  -- Resolved attribute (e.g. "fg"/"bg") of a highlight group, chasing links.
  ---@return integer? 24-bit colour, or nil if unset
  local function hl_attr(name, attr)
    return vim.api.nvim_get_hl(0, { name = name, link = false })[attr]
  end

  --- Blend two 24-bit colours: `weight` of `over` on top of `under`.
  ---@return string "#rrggbb"
  local function blend(over, under, weight)
    local function channels(colour)
      return math.floor(colour / 65536) % 256, math.floor(colour / 256) % 256, colour % 256
    end
    local o_r, o_g, o_b = channels(over)
    local u_r, u_g, u_b = channels(under)
    local function mix(o, u)
      return math.floor(o * weight + u * (1 - weight) + 0.5)
    end
    return string.format("#%02x%02x%02x", mix(o_r, u_r), mix(o_g, u_g), mix(o_b, u_b))
  end

  -- Themeable highlight groups for the explorer indicators.
  local function set_hl()
    vim.api.nvim_set_hl(0, "ReviewChanged", { link = "DiagnosticWarn", default = true })
    vim.api.nvim_set_hl(0, "ReviewReviewed", { link = "DiagnosticOk", default = true })
    -- Inline diff (M.toggle_diff) word-level highlight. gitsigns defaults these
    -- to TermCursor (a loud, wrong-hued cyan in most themes). Give each its own
    -- diff hue — the sign colour (green add / blue change / red delete) tinted
    -- 40% over the line background — so the within-line marks pop in the right
    -- colour instead of blue-on-red. Force (no default) to beat gitsigns' link;
    -- falls back to DiffText if the theme leaves a group's colours unset.
    local inline = {
      GitSignsAddInline = { sign = "GitSignsAdd", line = "DiffAdd" },
      GitSignsChangeInline = { sign = "GitSignsChange", line = "DiffChange" },
      GitSignsDeleteInline = { sign = "GitSignsDelete", line = "DiffDelete" },
    }
    for group, ref in pairs(inline) do
      local hue = hl_attr(ref.sign, "fg")
      local line_bg = hl_attr(ref.line, "bg")
      if hue and line_bg then
        vim.api.nvim_set_hl(0, group, { bg = blend(hue, line_bg, 0.4) })
      else
        vim.api.nvim_set_hl(0, group, { link = "DiffText" })
      end
    end
  end
  vim.api.nvim_create_autocmd("ColorScheme", { callback = set_hl })
  set_hl()

  vim.api.nvim_create_user_command("ReviewRefresh", M.refresh, { desc = "Recompute branch review status" })
  vim.api.nvim_create_user_command("ReviewToggle", M.toggle, { desc = "Toggle branch review mode" })
  vim.api.nvim_create_user_command("ReviewDiff", M.toggle_diff, { desc = "Toggle inline diff vs review base" })
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
  vim.keymap.set("n", "<leader>rd", M.toggle_diff, { desc = "Review: toggle inline diff view" })
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
