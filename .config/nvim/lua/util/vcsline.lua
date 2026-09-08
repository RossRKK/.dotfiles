-- The VCS half of the statusline, jj first.
--
-- lualine's stock `branch` component reads git's HEAD. In a colocated jj repo
-- HEAD is always detached at `@-`, so it shows a bare hash that names the
-- PARENT of the working copy -- true, useless. And its `diff` component reads
-- the dict gitsigns publishes, which is empty wherever jjsigns owns the gutter.
--
-- This module gives lualine two replacements:
--   * `branch()`: in a jj repo, the nearest bookmark below `@` with the distance
--     to it, then the change id -- `main+2 umzvrvxs`. Outside jj it defers to
--     lualine's own git branch, so a plain git repo looks as before.
--   * `diff_source()`: whichever of gitsigns' and jjsigns' status dicts the
--     current buffer carries, in the shape lualine's `diff` expects.
--
-- jj is asked with `--ignore-working-copy`: the answer is about `@` and its
-- ancestors, which a snapshot cannot change, and a snapshot per redraw would
-- feed the greeter's op-log watcher (see jjsigns for the same reasoning). The
-- call is async and cached per repo root, refreshed on the events that can
-- move `@` or a bookmark, so the statusline never blocks on a process.
--
-- The pure parts (parse, format) take strings so the spec drives them without
-- a repo.

local M = {}

--- Revset: the nearest bookmarked ancestors of `@`, everything between, and
--- `@` itself -- the `| @` keeps one line coming when no ancestor is
--- bookmarked at all. One line per commit, oldest first.
M.revset = "(heads(::@ & bookmarks())::@) | @"

--- Template: tab-separated per line -- an "@" mark for the working copy, the
--- change id, then the local bookmark names joined with commas.
M.template = 'if(current_working_copy, "@", "") ++ "\t" ++ change_id.shortest(8) ++ "\t"'
  .. ' ++ local_bookmarks.map(|b| b.name()).join(",") ++ "\n"'

---@class VcsLineInfo
---@field change_id string of `@`
---@field bookmark? string the nearest bookmark below (or on) `@`
---@field distance integer commits from that bookmark to `@`, 0 when it is on `@`

--- Parse the output of `jj log -r <revset> -T <template>`. The first line with
--- a bookmark is the base (jj prints newest first, so that is the nearest one);
--- the distance is the number of commits in the set without a bookmark, which
--- is `@` and everything between it and the base -- 0 when the bookmark sits
--- on `@`. Counting rather than positioning keeps it right whichever way jj
--- orders the lines, and with several bookmarked heads (a merge of two
--- bookmarked lines) still measures the unbookmarked stretch above them.
---@param out string
---@return VcsLineInfo?
function M.parse(out)
  local change_id, bookmark
  local distance = 0
  for line in vim.gsplit(out, "\n", { plain = true, trimempty = true }) do
    local mark, id, names = line:match("^(@?)\t(%w+)\t(.*)$")
    if id then
      if mark == "@" then
        change_id = id
      end
      if names == "" then
        distance = distance + 1
      elseif not bookmark then
        bookmark = names:match("^[^,]+")
      end
    end
  end
  if not change_id then
    return nil
  end
  return { change_id = change_id, bookmark = bookmark, distance = bookmark and distance or 0 }
end

--- Render the parsed info: `main+2 umzvrvxs`, `main umzvrvxs` when the bookmark
--- sits on `@`, or the bare change id when nothing below is bookmarked.
---@param info VcsLineInfo
---@return string
function M.format(info)
  if not info.bookmark then
    return info.change_id
  end
  local head = info.bookmark
  if info.distance > 0 then
    head = head .. "+" .. info.distance
  end
  return head .. " " .. info.change_id
end

--- Per-root cache of the rendered fragment and an in-flight marker.
---@type table<string, {text: string, busy: boolean}>
local cache = {}

--- The jj root for the current buffer's file (cwd for unnamed buffers).
---@return string?
local function root()
  local name = vim.api.nvim_buf_get_name(0)
  local dir = (name ~= "" and vim.bo.buftype == "" and vim.fs.dirname(name)) or vim.fn.getcwd()
  return vim.fs.root(dir, ".jj")
end

--- Ask jj about `root` and cache the result; one call in flight per root.
---@param r string
local function query(r)
  local c = cache[r]
  if c and c.busy then
    return
  end
  cache[r] = { text = c and c.text or "", busy = true }
  vim.system({
    "jj",
    "--color=never",
    "--no-pager",
    "--ignore-working-copy",
    "log",
    "--no-graph",
    "-r",
    M.revset,
    "-T",
    M.template,
  }, { cwd = r, text = true }, function(out)
    local text = cache[r] and cache[r].text or ""
    if out.code == 0 then
      local info = M.parse(out.stdout or "")
      text = info and M.format(info) or ""
    end
    cache[r] = { text = text, busy = false }
    vim.schedule(function()
      pcall(require("lualine").refresh, { place = { "statusline" } })
    end)
  end)
end

--- Forget the cached answer for the current root and ask again. Bound to the
--- events after which `@` or a bookmark may have moved.
function M.invalidate()
  local r = root()
  if r then
    cache[r] = nil
    query(r)
  end
end

local group = vim.api.nvim_create_augroup("vcsline", { clear = true })
-- BufWritePost: a save can create a new working-copy commit's first snapshot,
-- but not move `@` -- kept anyway as the cheapest "something happened" signal.
-- TermClose/TermLeave: jjui, jj-bond and a shell in the side terminal are where
-- `jj new`, `jj edit` and bookmark moves happen. FocusGained: the same from
-- another terminal window. DirChanged: another repo entirely.
vim.api.nvim_create_autocmd(
  { "BufWritePost", "TermClose", "TermLeave", "FocusGained", "DirChanged" },
  {
    group = group,
    callback = function()
      vim.schedule(M.invalidate)
    end,
  }
)

--- lualine component: the jj fragment, or the git branch outside jj.
---@return string
function M.branch()
  local r = root()
  if not r then
    return require("lualine.components.branch.git_branch").get_branch()
  end
  if not cache[r] then
    query(r)
  end
  return cache[r].text
end

--- lualine `diff` source: gitsigns' dict where gitsigns owns the buffer,
--- jjsigns' otherwise. Both use added/changed/removed; lualine wants modified.
---@return {added: integer, modified: integer, removed: integer}?
function M.diff_source()
  local d = vim.b.gitsigns_status_dict or vim.b.jjsigns_status_dict
  if not d then
    return nil
  end
  return { added = d.added, modified = d.changed, removed = d.removed }
end

return M
