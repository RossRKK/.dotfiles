-- The size of a PR's diff, broken down by how much review each file needs: a
-- 10k-line PR that is half lockfile churn and a 10k-line PR of new code are
-- different reviews, and that difference is what the review queue and the
-- greeter's PR overview are for.
--
-- Every changed file lands in one review tier (TIERS, in order of importance).
-- The headline +adds -dels is the plain sum of the reviewed tiers; generated
-- files are shown but count for nothing. "Generated" is GitHub's notion (the
-- files it collapses in a PR): `linguist-generated`, plus the lockfiles linguist
-- treats as generated without being told. `review-tier=<tier>` overrides it all.
--
-- Attributes are read with `git check-attr` rather than parsed here: nested
-- .gitattributes and gitignore-style patterns are git's to resolve, and it
-- reads them from any tree (--source), so the answer is the base branch's.

local M = {}

---@alias diffsize.Tier "interface"|"code"|"test"|"docs"|"generated"

---@class diffsize.TierInfo
---@field name diffsize.Tier
---@field reviewed boolean counted in the headline

-- Drawing order too: what most needs a reviewer's eye comes first.
---@type diffsize.TierInfo[]
M.TIERS = {
  { name = "interface", reviewed = true },
  { name = "code", reviewed = true },
  { name = "test", reviewed = true },
  { name = "docs", reviewed = true },
  { name = "generated", reviewed = false },
}

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

-- Lua patterns over "/" .. path, so a directory pattern also matches at the root.
M.TEST_PATTERNS = {
  "/tests?/",
  "/__tests__/",
  "/spec/",
  "_spec%.[^/]+$",
  "_test%.[^/]+$",
  "/test_[^/]*%.py$",
  "%.test%.[^/]+$",
  "%.spec%.[^/]+$",
  "Tests?%.[^/]+$",
}

-- Prose extensions counted as docs when no attribute says otherwise.
M.DOC_EXTENSIONS = { md = true, markdown = true, rst = true, adoc = true }

-- Prose files that state what a change promises (specs, intents) are interface.
local INTERFACE_PROSE = { md = true, txt = true }
local INTERFACE_WORDS = { "spec", "intent" }

---@class diffsize.Attrs
---@field tier diffsize.Tier? review-tier, when it names a tier
---@field generated boolean? linguist-generated, when set either way
---@field documentation boolean? linguist-documentation, when set either way

-- check-attr's values for a boolean attribute; "unspecified" is absent.
local FLAG_VALUES = { set = true, ["true"] = true, unset = false, ["false"] = false }

local TIER_NAMES = {} ---@type table<string, diffsize.Tier>
for _, t in ipairs(M.TIERS) do
  TIER_NAMES[t.name] = t.name
end

-- The attributes tier() reads: each one's diffsize.Attrs field and its known values.
local ATTRS = {
  { name = "linguist-generated", field = "generated", values = FLAG_VALUES },
  { name = "linguist-documentation", field = "documentation", values = FLAG_VALUES },
  { name = "review-tier", field = "tier", values = TIER_NAMES },
}

--- `git check-attr` for the attributes tier() reads, over NUL-separated paths on stdin.
---@param source string? a tree-ish to read .gitattributes from (default: the worktree)
---@return string[]
function M.attr_cmd(source)
  local cmd = { "git", "check-attr", "-z", "--stdin" }
  if source then
    vim.list_extend(cmd, { "--source", source })
  end
  for _, attr in ipairs(ATTRS) do
    cmd[#cmd + 1] = attr.name
  end
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
---@return table<string, diffsize.Attrs>
function M.parse_attrs(out)
  local by_name = {}
  for _, attr in ipairs(ATTRS) do
    by_name[attr.name] = attr
  end
  local fields = vim.split(out, "\0", { plain = true })
  local attrs = {}
  for i = 1, #fields - 2, 3 do
    local path, attr = fields[i], by_name[fields[i + 1]]
    attrs[path] = attrs[path] or {}
    if attr then
      attrs[path][attr.field] = attr.values[fields[i + 2]]
    end
  end
  return attrs
end

-- First match wins; a file matching none is code.
---@type { tier: diffsize.Tier, matches: fun(path: string, attrs: diffsize.Attrs): boolean }[]
local RULES = {
  {
    tier = "generated",
    matches = function(path, attrs)
      return M.explicit_or(attrs.generated, M.LOCKFILES[vim.fs.basename(path)] == true)
    end,
  },
  {
    tier = "interface",
    matches = function(path)
      return M.is_interface(path)
    end,
  },
  {
    tier = "docs",
    matches = function(path, attrs)
      return M.explicit_or(attrs.documentation, M.DOC_EXTENSIONS[M.extension(path)] == true)
    end,
  },
  {
    tier = "test",
    matches = function(path)
      return M.is_test(path)
    end,
  },
}

--- The review tier of `path`, given its attributes.
---@param path string
---@param attrs diffsize.Attrs? from parse_attrs (nil: none known)
---@return diffsize.Tier
function M.tier(path, attrs)
  attrs = attrs or {}
  if attrs.tier then
    return attrs.tier
  end
  for _, rule in ipairs(RULES) do
    if rule.matches(path, attrs) then
      return rule.tier
    end
  end
  return "code"
end

---@param explicit boolean?
---@param default boolean
---@return boolean
function M.explicit_or(explicit, default)
  if explicit == nil then
    return default
  end
  return explicit
end

---@param path string
---@return boolean
function M.is_interface(path)
  local ext = M.extension(path)
  if ext == "proto" then
    return true
  end
  if not INTERFACE_PROSE[ext] then
    return false
  end
  local name = vim.fs.basename(path):lower()
  for _, word in ipairs(INTERFACE_WORDS) do
    if name:find(word, 1, true) then
      return true
    end
  end
  return false
end

---@param path string
---@return boolean
function M.is_test(path)
  local rooted = "/" .. path
  for _, pattern in ipairs(M.TEST_PATTERNS) do
    if rooted:find(pattern) then
      return true
    end
  end
  return false
end

---@param path string
---@return string? lowercased
function M.extension(path)
  local ext = vim.fs.basename(path):match("%.([^.]+)$")
  return ext and ext:lower()
end

---@class diffsize.Count
---@field additions integer
---@field deletions integer

---@class diffsize.Size
---@field tiers table<diffsize.Tier, diffsize.Count> every tier, zero when untouched

--- Sum a PR's per-file changes by review tier.
---@param changes { path: string, additions: integer, deletions: integer }[]
---@param attrs table<string, diffsize.Attrs>? from parse_attrs
---@return diffsize.Size
function M.summarize(changes, attrs)
  attrs = attrs or {}
  local tiers = {}
  for _, t in ipairs(M.TIERS) do
    tiers[t.name] = { additions = 0, deletions = 0 }
  end
  for _, c in ipairs(changes) do
    local count = tiers[M.tier(c.path, attrs[c.path])]
    count.additions = count.additions + (c.additions or 0)
    count.deletions = count.deletions + (c.deletions or 0)
  end
  return { tiers = tiers }
end

--- The headline: the reviewed tiers summed.
---@param size diffsize.Size
---@return diffsize.Count
function M.headline(size)
  local sum = { additions = 0, deletions = 0 }
  for _, t in ipairs(M.TIERS) do
    if t.reviewed then
      sum.additions = sum.additions + size.tiers[t.name].additions
      sum.deletions = sum.deletions + size.tiers[t.name].deletions
    end
  end
  return sum
end

--- Lines a tier touches, additions and deletions alike.
---@param size diffsize.Size
---@param tier diffsize.Tier
---@return integer
function M.lines(size, tier)
  return size.tiers[tier].additions + size.tiers[tier].deletions
end

--- "+12 -3": the headline, as every view shows it.
---@param size diffsize.Size
---@return string adds, string dels
function M.counts(size)
  local sum = M.headline(size)
  return "+" .. sum.additions, "-" .. sum.deletions
end

--- A line count short enough for a legend: 950, 9.4k, 12k, 1.3M.
---@param n integer
---@return string
function M.abbrev(n)
  for _, unit in ipairs({ { 1e6, "M" }, { 1e3, "k" } }) do
    if n >= unit[1] then
      local scaled = n / unit[1]
      local fmt = scaled < 10 and "%.1f" or "%.0f"
      return (fmt:format(scaled):gsub("%.0$", "")) .. unit[2]
    end
  end
  return tostring(n)
end

--- The legend, one entry per touched tier: "120 interface", "9.4k generated".
---@param size diffsize.Size
---@return { tier: diffsize.Tier, text: string }[]
function M.legend(size)
  local out = {}
  for _, t in ipairs(M.TIERS) do
    local n = M.lines(size, t.name)
    if n > 0 then
      out[#out + 1] = { tier = t.name, text = ("%s %s"):format(M.abbrev(n), t.name) }
    end
  end
  return out
end

local SEP = " \u{00b7} "

--- The size line in markdown, for views without colour: "**+12 -3** · 10 code · 5 test".
---@param size diffsize.Size
---@return string
function M.markdown(size)
  local adds, dels = M.counts(size)
  local parts = { ("**%s %s**"):format(adds, dels) }
  for _, entry in ipairs(M.legend(size)) do
    parts[#parts + 1] = entry.text
  end
  return table.concat(parts, SEP)
end

--- Highlighted chunks, { text, hl } pairs: the counts, then the legend in `dim`.
---@param size diffsize.Size
---@param dim string the caller's subdued highlight
---@return { [1]: string, [2]: string? }[]
function M.chunks(size, dim)
  local adds, dels = M.counts(size)
  local out = { { adds, "Added" }, { " " }, { dels, "Removed" } }
  for i, entry in ipairs(M.legend(size)) do
    out[#out + 1] = { i == 1 and "  " or SEP, dim }
    out[#out + 1] = { entry.text, dim }
  end
  return out
end

return M
