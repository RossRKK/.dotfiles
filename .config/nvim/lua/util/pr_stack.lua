-- The stack of PRs around a branch, read from my open PRs (the review queue's
-- `mine` list): PRs chain through their base branches, the way GitHub models a
-- stack and retargets it as the bottom merges. No fetch of its own.

local M = {}

---@class pr_stack.Row
---@field pr reviewqueue.PR
---@field verdict reviewqueue.Verdict
---@field current boolean the PR of the branch checked out

---@class pr_stack.Stack
---@field rows pr_stack.Row[] top of the stack first, each PR above the one it targets
---@field trunk string the branch the bottom PR targets

--- The stack `branch`'s PR belongs to: every PR chained to the bottom of its
--- base chain, so siblings forked off a lower PR are in it too. A PR standing
--- alone is a stack of one. Nil when the branch has no PR in `items`.
---@param items { pr: reviewqueue.PR, verdict: reviewqueue.Verdict }[]
---@param branch string?
---@return pr_stack.Stack?
function M.of(items, branch)
  local by_head, on = {}, {}
  for _, it in ipairs(items) do
    by_head[it.pr.head] = it
    on[it.pr.base] = on[it.pr.base] or {}
    table.insert(on[it.pr.base], it)
  end
  local bottom = branch and by_head[branch]
  if not bottom then
    return nil
  end
  -- Seen guards a base cycle, which GitHub allows between open PRs.
  local seen = { [bottom] = true }
  while by_head[bottom.pr.base] and not seen[by_head[bottom.pr.base]] do
    bottom = by_head[bottom.pr.base]
    seen[bottom] = true
  end

  local rows, placed = {}, {}
  local function place(it)
    placed[it] = true
    local children = vim.tbl_filter(function(c)
      return not placed[c]
    end, on[it.pr.head] or {})
    table.sort(children, function(a, b)
      return a.pr.number > b.pr.number
    end)
    for _, child in ipairs(children) do
      place(child)
    end
    rows[#rows + 1] = { pr = it.pr, verdict = it.verdict, current = it.pr.head == branch }
  end
  place(bottom)
  return { rows = rows, trunk = bottom.pr.base }
end

return M
