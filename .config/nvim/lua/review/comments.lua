-- GitHub PR line comments, in your normal file buffers.
--
-- The companion to lua/review/init.lua's triage: while reviewing a file you've
-- actually got open, drop a comment on the line under the cursor (or a visual
-- range) and it posts to the branch's open PR via the `gh` CLI. Everyone's line
-- comments render inline as virtual text, shown/hidden with review mode.
--
-- The PR is found from the active branch: none -> stay quiet; one -> use it;
-- several -> ask once (remembered per branch). Rendering reads a cache, so only
-- an explicit refresh or turning review mode on hits the network.

local M = {}

-- rel path -> list of raw review-comment objects from the GitHub API.
M.by_path = {}
-- Repo toplevel, set whenever we resolve one.
M.root = nil
-- Remembers a manual PR choice for a branch so we don't re-prompt: {branch, number}.
M.pr_choice = nil
-- The authenticated GitHub login, cached; used to find your own comments to edit.
M.viewer = nil
-- Whether inline comments are currently drawn (driven by review mode).
M.shown = false
-- Absolute paths of files with comments, plus their ancestor dirs, for the tree
-- decorator. Rebuilt on each fetch; empty while comments are hidden.
M.marked = {}

local ns = vim.api.nvim_create_namespace("review_comments")

--- Run a command async, yielding until it exits. Returns the vim.system result
--- object ({ code, stdout, stderr }). MUST run inside a coroutine.
---@param cmd string[]
---@param cwd string?
local function sh(cmd, cwd)
  local co = assert(coroutine.running(), "review.comments: must run inside a coroutine")
  vim.system(cmd, { text = true, cwd = cwd }, function(obj)
    vim.schedule(function()
      coroutine.resume(co, obj)
    end)
  end)
  return coroutine.yield()
end

--- Run gh and JSON-decode stdout. Returns (value, nil) or (nil, errmsg).
---@param args string[]
---@param cwd string?
local function gh_json(args, cwd)
  local obj = sh(vim.list_extend({ "gh" }, args), cwd)
  if obj.code ~= 0 then
    return nil, (obj.stderr ~= "" and obj.stderr or "gh exited " .. obj.code)
  end
  local ok, decoded = pcall(vim.json.decode, obj.stdout)
  if not ok then
    return nil, "could not parse gh JSON"
  end
  return decoded
end

--- Drive an async body on a coroutine, surfacing errors as a notification.
---@param fn fun()
local function run(fn)
  coroutine.wrap(function()
    local ok, err = pcall(fn)
    if not ok then
      vim.notify("review.comments: " .. tostring(err), vim.log.levels.ERROR)
    end
  end)()
end

--- vim.ui.select as a coroutine call. Returns the chosen 1-based index, or nil.
--- Handles both the async pickers (dressing/telescope: callback fires later, so
--- we yield and resume) and Neovim's builtin select (callback fires *before*
--- vim.ui.select returns — resuming a still-running coroutine would error, so we
--- just hand back the answer directly).
---@param items string[]
---@param opts table
local function pick(items, opts)
  local co = coroutine.running()
  local answered, answer = false, nil
  vim.ui.select(items, opts, function(_, idx)
    answered, answer = true, idx
    if coroutine.status(co) == "suspended" then
      coroutine.resume(co, idx)
    end
  end)
  if answered then
    return answer
  end
  return coroutine.yield()
end

--- Repo toplevel for the current buffer (cached on M.root). nil outside a repo.
---@return string?
local function current_root()
  local root = vim.fs.root(0, ".git")
  M.root = root and vim.fs.normalize(root) or M.root
  return root and vim.fs.normalize(root) or nil
end

--- A buffer's path relative to `root`, or nil if it's not under it.
---@param buf integer
---@param root string
---@return string?
local function rel_of(buf, root)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return nil
  end
  name = vim.fs.normalize(name)
  if name ~= root and name:sub(1, #root + 1) ~= root .. "/" then
    return nil
  end
  return name:sub(#root + 2)
end

--- The open PR for the branch checked out in `root`. Returns {number, head} or
--- nil (no PR, or the user dismissed the picker). Prompts once when a branch has
--- several open PRs and remembers the choice.
---@param root string
---@return { number: integer, head: string }?
local function resolve_pr(root)
  local branch = vim.trim(sh({ "git", "-C", root, "branch", "--show-current" }).stdout or "")
  if branch == "" then
    return nil
  end
  local prs = gh_json({ "pr", "list", "--head", branch, "--state", "open", "--json", "number,headRefOid,title" }, root)
  if not prs or #prs == 0 then
    return nil
  end

  local chosen
  if #prs == 1 then
    chosen = prs[1]
  elseif M.pr_choice and M.pr_choice.branch == branch then
    for _, pr in ipairs(prs) do
      if pr.number == M.pr_choice.number then
        chosen = pr
      end
    end
    chosen = chosen or prs[1]
  else
    local labels = {}
    for _, pr in ipairs(prs) do
      labels[#labels + 1] = ("#%d  %s"):format(pr.number, pr.title)
    end
    local idx = pick(labels, { prompt = "Multiple open PRs for this branch:" })
    if not idx then
      return nil
    end
    chosen = prs[idx]
    M.pr_choice = { branch = branch, number = chosen.number }
  end
  return { number = chosen.number, head = chosen.headRefOid }
end

--- The authenticated GitHub login (cached). Used to find your own comments.
---@param root string
---@return string?
local function resolve_viewer(root)
  if M.viewer then
    return M.viewer
  end
  local obj = sh({ "gh", "api", "user", "--jq", ".login" }, root)
  if obj.code == 0 then
    M.viewer = vim.trim(obj.stdout)
  end
  return M.viewer
end

--- The cached comments anchored at the current cursor line (a thread), with the
--- context needed to act on them. Returns (thread, rel, root) or nil.
---@return table[]?, string?, string?
local function thread_at_cursor()
  local root = current_root()
  if not root then
    return nil
  end
  local rel = rel_of(vim.api.nvim_get_current_buf(), root)
  if not rel then
    return nil
  end
  local line = vim.fn.line(".")
  local thread = {}
  for _, c in ipairs(M.by_path[rel] or {}) do
    if (c.line or c.original_line) == line then
      thread[#thread + 1] = c
    end
  end
  return thread, rel, root
end

--- A scratch float to compose text. Calls on_submit(body, close) on <C-s>.
--- `initial` prefills it (and skips insert mode, e.g. when editing).
---@param title string
---@param initial string[]?
---@param on_submit fun(body: string, close: fun())
local function open_input(title, initial, on_submit)
  local input = vim.api.nvim_create_buf(false, true)
  vim.bo[input].filetype = "markdown"
  vim.bo[input].bufhidden = "wipe"
  if initial and #initial > 0 then
    vim.api.nvim_buf_set_lines(input, 0, -1, false, initial)
  end
  local width = math.min(80, vim.o.columns - 4)
  local win = vim.api.nvim_open_win(input, true, {
    relative = "editor",
    width = width,
    height = 8,
    row = vim.o.lines - 11,
    col = math.floor((vim.o.columns - width) / 2),
    border = "rounded",
    title = (" %s  ·  <C-s> send  ·  q cancel "):format(title),
    style = "minimal",
  })

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  local function submit()
    local body = vim.trim(table.concat(vim.api.nvim_buf_get_lines(input, 0, -1, false), "\n"))
    if body == "" then
      close()
      return
    end
    on_submit(body, close)
  end
  vim.keymap.set({ "n", "i" }, "<C-s>", submit, { buffer = input, desc = "Send" })
  vim.keymap.set("n", "q", close, { buffer = input, desc = "Cancel" })
  if not (initial and #initial > 0) then
    vim.cmd("startinsert")
  end
end

--- Draw the cached comments for one buffer (no network). Clears first, so it's
--- safe to call on any redraw. A no-op while comments are hidden.
---@param buf integer
local function render_buf(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if not M.shown or not M.root then
    return
  end
  local rel = rel_of(buf, M.root)
  local list = rel and M.by_path[rel]
  if not list then
    return
  end

  -- Group a line's comments into one stacked thread. `line` is the comment's
  -- position in the file at the PR's latest commit; original_line is the
  -- fallback when GitHub marks it outdated (line == nil).
  local by_line = {}
  for _, c in ipairs(list) do
    local anchor = c.line or c.original_line
    if anchor then
      by_line[anchor] = by_line[anchor] or {}
      table.insert(by_line[anchor], c)
    end
  end

  local last = vim.api.nvim_buf_line_count(buf)
  for anchor, thread in pairs(by_line) do
    if anchor >= 1 and anchor <= last then
      local virt = {}
      for _, c in ipairs(thread) do
        local header = { { "▌ ", "ReviewCommentSign" }, { "@" .. c.user.login, "ReviewCommentAuthor" } }
        if c.side == "LEFT" then
          header[#header + 1] = { "  (old side)", "ReviewComment" }
        end
        table.insert(virt, header)
        for _, line in ipairs(vim.split((c.body or ""):gsub("\r", ""), "\n", { plain = true })) do
          table.insert(virt, { { "▌ ", "ReviewCommentSign" }, { line, "ReviewComment" } })
        end
      end
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, anchor - 1, 0, { virt_lines = virt })
    end
  end
end

--- Fetch the branch PR's line comments and (re)draw every loaded buffer.
local function fetch_render()
  run(function()
    local root = current_root()
    if not root then
      return
    end
    local pr = resolve_pr(root)
    if not pr then
      return -- no PR for this branch: stay quiet
    end
    -- 100 covers all but the busiest PRs; page beyond that only if it bites.
    local endpoint = ("repos/:owner/:repo/pulls/%d/comments?per_page=100"):format(pr.number)
    local comments, err = gh_json({ "api", endpoint }, root)
    if not comments then
      vim.notify("review: couldn't fetch comments: " .. tostring(err), vim.log.levels.WARN)
      return
    end

    local by_path = {}
    for _, c in ipairs(comments) do
      if c.path then
        by_path[c.path] = by_path[c.path] or {}
        table.insert(by_path[c.path], c)
      end
    end
    M.by_path = by_path
    if #comments >= 100 then
      vim.notify("review: showing the first 100 PR comments", vim.log.levels.WARN)
    end

    -- Mark commented files and every ancestor dir, for the tree decorator.
    local marked = {}
    local nroot = vim.fs.normalize(root)
    for rel in pairs(by_path) do
      local abs = vim.fs.normalize(root .. "/" .. rel)
      marked[abs] = true
      local dir = vim.fs.dirname(abs)
      while dir and #dir >= #nroot do
        marked[dir] = true
        if dir == nroot then
          break
        end
        dir = vim.fs.dirname(dir)
      end
    end
    M.marked = marked

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) then
        render_buf(buf)
      end
    end
    require("review").redraw_tree()
  end)
end

--- Whether a file or folder has PR comments (for the tree decorator). False
--- while comments are hidden.
---@param abs string?
---@return boolean
function M.has_comments(abs)
  if not M.shown or not abs then
    return false
  end
  return M.marked[vim.fs.normalize(abs)] == true
end

--- Post a review comment on the current file. `end_line` is the anchor line;
--- `start_line` (or nil) makes it a multi-line comment spanning start..end.
---@param start_line integer?
---@param end_line integer
function M.comment(start_line, end_line)
  local root = current_root()
  if not root then
    vim.notify("review: not in a git repo", vim.log.levels.WARN)
    return
  end
  local rel = rel_of(vim.api.nvim_get_current_buf(), root)
  if not rel then
    vim.notify("review: this buffer isn't a file in the repo", vim.log.levels.WARN)
    return
  end

  local title = ("PR comment on %s:%d"):format(vim.fs.basename(rel), end_line)
  open_input(title, nil, function(body, close)
    run(function()
      local pr = resolve_pr(root)
      if not pr then
        vim.notify("review: no open PR for this branch", vim.log.levels.INFO)
        return
      end
      local args = {
        "api", "--method", "POST",
        ("repos/:owner/:repo/pulls/%d/comments"):format(pr.number),
        "-f", "body=" .. body,
        "-f", "commit_id=" .. pr.head,
        "-f", "path=" .. rel,
        "-F", "line=" .. end_line,
        "-f", "side=RIGHT",
      }
      if start_line and start_line < end_line then
        vim.list_extend(args, { "-F", "start_line=" .. start_line, "-f", "start_side=RIGHT" })
      end
      local obj = sh(vim.list_extend({ "gh" }, args), root)
      if obj.code == 0 then
        close()
        vim.notify("review: comment posted")
        fetch_render()
      else
        -- Most often: the line isn't part of the PR diff (GitHub 422s). Keep the
        -- float open so the text isn't lost.
        vim.notify("review: post failed: " .. (obj.stderr ~= "" and obj.stderr or "gh error"), vim.log.levels.ERROR)
      end
    end)
  end)
end

--- Reply to the comment thread anchored at the cursor line.
function M.reply()
  local thread, _, root = thread_at_cursor()
  if not thread or #thread == 0 then
    vim.notify("review: no PR comment on this line (is review mode on?)", vim.log.levels.INFO)
    return
  end
  local target = thread[1].id -- the thread root; GitHub attaches the reply to it
  open_input("Reply", nil, function(body, close)
    run(function()
      local pr = resolve_pr(root)
      if not pr then
        vim.notify("review: no open PR for this branch", vim.log.levels.INFO)
        return
      end
      local obj = sh({
        "gh", "api", "--method", "POST",
        ("repos/:owner/:repo/pulls/%d/comments/%d/replies"):format(pr.number, target),
        "-f", "body=" .. body,
      }, root)
      if obj.code == 0 then
        close()
        vim.notify("review: reply posted")
        fetch_render()
      else
        vim.notify("review: reply failed: " .. (obj.stderr ~= "" and obj.stderr or "gh error"), vim.log.levels.ERROR)
      end
    end)
  end)
end

--- Edit one of your own comments in the thread at the cursor line.
function M.edit()
  local thread, _, root = thread_at_cursor()
  if not thread or #thread == 0 then
    vim.notify("review: no PR comment on this line (is review mode on?)", vim.log.levels.INFO)
    return
  end
  run(function()
    local login = resolve_viewer(root)
    local mine = {}
    for _, c in ipairs(thread) do
      if login and c.user.login == login then
        mine[#mine + 1] = c
      end
    end
    if #mine == 0 then
      vim.notify("review: no comment of yours on this line", vim.log.levels.INFO)
      return
    end
    local target = mine[1]
    if #mine > 1 then
      local labels = {}
      for _, c in ipairs(mine) do
        labels[#labels + 1] = (c.body:gsub("%s+", " ")):sub(1, 50)
      end
      local idx = pick(labels, { prompt = "Edit which of your comments?" })
      if not idx then
        return
      end
      target = mine[idx]
    end

    -- Defer: when a picker ran, this coroutine resumes inside vim.ui.select's
    -- teardown, where opening a float races the picker closing its window. A
    -- scheduled tick lets that settle first. (Harmless on the single-match path.)
    local initial = vim.split(target.body:gsub("\r", ""), "\n", { plain = true })
    vim.schedule(function()
      open_input("Edit comment", initial, function(body, close)
        run(function()
          local obj = sh({
            "gh", "api", "--method", "PATCH",
            ("repos/:owner/:repo/pulls/comments/%d"):format(target.id),
            "-f", "body=" .. body,
          }, root)
          if obj.code == 0 then
            close()
            vim.notify("review: comment updated")
            fetch_render()
          else
            vim.notify("review: edit failed: " .. (obj.stderr ~= "" and obj.stderr or "gh error"), vim.log.levels.ERROR)
          end
        end)
      end)
    end)
  end)
end

--- Show or hide inline comments. Showing fetches from GitHub; hiding just clears.
---@param on boolean
function M.set_shown(on)
  M.shown = on
  if on then
    fetch_render()
  else
    M.marked = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) then
        vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      end
    end
    require("review").redraw_tree()
  end
end

--- Re-fetch from GitHub and redraw (manual refresh).
function M.refresh()
  if M.shown then
    fetch_render()
  end
end

function M.setup()
  local function set_hl()
    vim.api.nvim_set_hl(0, "ReviewComment", { link = "Comment", default = true })
    vim.api.nvim_set_hl(0, "ReviewCommentAuthor", { link = "Title", default = true })
    vim.api.nvim_set_hl(0, "ReviewCommentSign", { link = "DiagnosticInfo", default = true })
  end
  vim.api.nvim_create_autocmd("ColorScheme", { callback = set_hl })
  set_hl()

  -- Draw cached comments on buffers as they load/show (cheap; no network).
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufWinEnter" }, {
    callback = function(a)
      if M.shown then
        render_buf(a.buf)
      end
    end,
  })

  vim.keymap.set("n", "<leader>rc", function()
    M.comment(nil, vim.fn.line("."))
  end, { desc = "Review: comment on line (PR)" })
  vim.keymap.set("x", "<leader>rc", function()
    local a, b = vim.fn.line("v"), vim.fn.line(".")
    if a > b then
      a, b = b, a
    end
    M.comment(a == b and nil or a, b)
  end, { desc = "Review: comment on range (PR)" })
  vim.keymap.set("n", "<leader>ra", M.reply, { desc = "Review: reply to PR comment on line" })
  vim.keymap.set("n", "<leader>re", M.edit, { desc = "Review: edit your PR comment on line" })
  vim.keymap.set("n", "<leader>rC", M.refresh, { desc = "Review: refresh PR comments" })

  vim.api.nvim_create_user_command("ReviewComment", function()
    M.comment(nil, vim.fn.line("."))
  end, { desc = "Comment on the current line in the branch PR" })
  vim.api.nvim_create_user_command("ReviewReply", M.reply, { desc = "Reply to the PR comment on this line" })
  vim.api.nvim_create_user_command("ReviewEditComment", M.edit, { desc = "Edit your PR comment on this line" })
  vim.api.nvim_create_user_command("ReviewCommentsRefresh", M.refresh, { desc = "Re-fetch PR comments" })
end

return M
