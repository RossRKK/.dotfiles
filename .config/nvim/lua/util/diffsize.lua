-- The size of a PR's diff, without the generated files: a 40-line change that
-- regenerates a lockfile reads as +3000 otherwise, and that number is what the
-- review queue and the greeter's PR overview are for -- how big a review is.
--
-- "Generated" is GitHub's notion (the files it collapses in a PR): the
-- `linguist-generated` attribute from .gitattributes, plus the lockfiles that
-- linguist treats as generated without being told. An explicit
-- `linguist-generated=false` (or `-linguist-generated`) keeps a file counted.
--
-- The attribute is read with `git check-attr` rather than parsed here: nested
-- .gitattributes and gitignore-style patterns are git's to resolve, and it
-- reads them from any tree (--source), so the answer is the base branch's.

local M = {}

-- Basenames counted as generated unless .gitattributes says otherwise.
M.LOCKFILES = {
  ["Cargo.lock"] = true,
  ["package-lock.json"] = true,
  ["npm-shrinkwrap.json"] = true,
  ["yarn.lock"] = true,
  ["pnpm-lock.yaml"] = true,
  ["bun.lock"] = true,
  ["deno.lock"] = true,
  ["poetry.lock"] = true,
  ["uv.lock"] = true,
  ["pdm.lock"] = true,
  ["Pipfile.lock"] = true,
  ["composer.lock"] = true,
  ["Gemfile.lock"] = true,
  ["go.sum"] = true,
  ["Gopkg.lock"] = true,
  ["flake.lock"] = true,
  ["Package.resolved"] = true,
  ["mix.lock"] = true,
  ["pubspec.lock"] = true,
}

--- `git check-attr` for linguist-generated over NUL-separated paths on stdin.
---@param source string? a tree-ish to read .gitattributes from (default: the worktree)
---@return string[]
function M.attr_cmd(source)
  local cmd = { "git", "check-attr", "-z", "--stdin" }
  if source then
    vim.list_extend(cmd, { "--source", source })
  end
  cmd[#cmd + 1] = "linguist-generated"
  return cmd
end

--- The stdin for attr_cmd.
---@param paths string[]
---@return string
function M.attr_input(paths)
  return #paths == 0 and "" or table.concat(paths, "\0") .. "\0"
end

--- Parse `git check-attr -z` output (path NUL attr NUL value NUL, repeated).
---@param out string
---@return table<string, string> path -> value (set|unset|unspecified|<string>)
function M.parse_attrs(out)
  local fields = vim.split(out, "\0", { plain = true })
  local attrs = {}
  for i = 1, #fields - 2, 3 do
    attrs[fields[i]] = fields[i + 2]
  end
  return attrs
end

--- Is `path` generated, given its linguist-generated value (nil: unknown)?
---@param path string
---@param value string?
---@return boolean
function M.is_generated(path, value)
  if value == "set" or value == "true" then
    return true
  end
  if value == "unset" or value == "false" then
    return false
  end
  return M.LOCKFILES[vim.fs.basename(path)] == true
end

---@class diffsize.Size
---@field additions integer
---@field deletions integer
---@field files integer
---@field generated { files: integer, additions: integer, deletions: integer }

--- Sum a PR's per-file changes, generated files counted apart.
---@param changes { path: string, additions: integer, deletions: integer }[]
---@param attrs table<string, string>? from parse_attrs
---@return diffsize.Size
function M.summarize(changes, attrs)
  attrs = attrs or {}
  local size = { additions = 0, deletions = 0, files = 0 }
  local gen = { additions = 0, deletions = 0, files = 0 }
  for _, c in ipairs(changes) do
    local t = M.is_generated(c.path, attrs[c.path]) and gen or size
    t.files = t.files + 1
    t.additions = t.additions + (c.additions or 0)
    t.deletions = t.deletions + (c.deletions or 0)
  end
  size.generated = gen
  return size
end

--- "+12 -3": the part of a size every view shows.
---@param size diffsize.Size
---@return string adds, string dels
function M.counts(size)
  return "+" .. size.additions, "-" .. size.deletions
end

--- " in 4 files · 1 generated excluded": what follows the counts.
---@param size diffsize.Size
---@return string
function M.detail(size)
  local out = (" in %d file%s"):format(size.files, size.files == 1 and "" or "s")
  if size.generated.files > 0 then
    out = out .. (" \u{00b7} %d generated excluded"):format(size.generated.files)
  end
  return out
end

--- Highlighted chunks, { text, hl } pairs: the counts, then detail() in `dim`.
---@param size diffsize.Size
---@param dim string the caller's subdued highlight
---@return { [1]: string, [2]: string? }[]
function M.chunks(size, dim)
  local adds, dels = M.counts(size)
  return { { adds, "Added" }, { " " }, { dels, "Removed" }, { M.detail(size), dim } }
end

return M
