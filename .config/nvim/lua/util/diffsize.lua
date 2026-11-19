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

---@alias diffsize.Tier "spec"|"proto"|"code"|"test"|"docs"|"generated"

---@class diffsize.TierInfo
---@field name diffsize.Tier
---@field reviewed boolean counted in the headline
---@field hl string its highlight group, linked to `link` so it follows the colourscheme
---@field link string
---@field glyphs string[] bar glyphs from the narrowest to a full cell

-- Left eighth blocks, for a bar precise to an eighth of a cell.
local EIGHTHS =
  { "\u{258f}", "\u{258e}", "\u{258d}", "\u{258c}", "\u{258b}", "\u{258a}", "\u{2589}", "\u{2588}" }

-- Drawing order too: what most needs a reviewer's eye comes first.
---@type diffsize.TierInfo[]
M.TIERS = {
  { name = "spec", reviewed = true, hl = "DiffSizeSpec", link = "Special", glyphs = EIGHTHS },
  { name = "proto", reviewed = true, hl = "DiffSizeProto", link = "Type", glyphs = EIGHTHS },
  { name = "code", reviewed = true, hl = "DiffSizeCode", link = "Function", glyphs = EIGHTHS },
  { name = "test", reviewed = true, hl = "DiffSizeTest", link = "String", glyphs = EIGHTHS },
  { name = "docs", reviewed = true, hl = "DiffSizeDocs", link = "Constant", glyphs = EIGHTHS },
  -- Shaded whole cells: dimmed, and set apart from the reviewed tiers by more than colour.
  {
    name = "generated",
    reviewed = false,
    hl = "DiffSizeGenerated",
    link = "Comment",
    glyphs = { "\u{2591}" },
  },
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

-- Prose files that state what a change promises: specs and intents.
local SPEC_EXTENSIONS = { md = true, txt = true }
local SPEC_WORDS = { "spec", "intent" }

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
    tier = "spec",
    matches = function(path)
      return M.is_spec(path)
    end,
  },
  {
    tier = "proto",
    matches = function(path)
      return M.extension(path) == "proto"
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
function M.is_spec(path)
  if not SPEC_EXTENSIONS[M.extension(path)] then
    return false
  end
  local name = vim.fs.basename(path):lower()
  for _, word in ipairs(SPEC_WORDS) do
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

--- The legend, one entry per touched tier: "120 spec", "9.4k generated".
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

--- Highlighted chunks, { text, hl } pairs: the counts, the bar, then the
--- legend in the bar's colours with `dim` between its entries.
---@param size diffsize.Size
---@param dim string the caller's subdued highlight
---@return { [1]: string, [2]: string? }[]
function M.chunks(size, dim)
  M.define_highlights()
  local hl = {}
  for _, t in ipairs(M.TIERS) do
    hl[t.name] = t.hl
  end
  local adds, dels = M.counts(size)
  local out = { { adds, "Added" }, { " " }, { dels, "Removed" } }
  for i, segment in ipairs(M.bar(size, M.BAR_CELLS)) do
    if i == 1 then
      out[#out + 1] = { "  " }
    end
    out[#out + 1] = { segment.text, hl[segment.tier] }
  end
  for i, entry in ipairs(M.legend(size)) do
    out[#out + 1] = { i == 1 and "  " or SEP, dim }
    out[#out + 1] = { entry.text, hl[entry.tier] }
  end
  return out
end

M.BAR_CELLS = 16

--- The bar: the reviewed tiers fill `cells` in proportion to the lines each
--- touches; unreviewed ones trail at the same scale, capped at half the bar so
--- a lockfile can't squeeze the review out of it (the legend has its size).
--- Each run is at its glyphs' precision and never less than its narrowest glyph.
---@param size diffsize.Size
---@param cells integer the width the reviewed lines fill
---@return { tier: diffsize.Tier, text: string }[]
function M.bar(size, cells)
  local sum = M.headline(size)
  local reviewed = sum.additions + sum.deletions
  local out = {}
  for _, t in ipairs(M.TIERS) do
    local n = M.lines(size, t.name)
    if n > 0 then
      -- With nothing reviewed this is inf, which only an unreviewed tier can reach.
      local width = n / reviewed * cells
      if not t.reviewed then
        width = math.min(width, cells / 2)
      end
      local steps = #t.glyphs
      local units = math.max(1, math.floor(width * steps + 0.5))
      local full, rest = math.floor(units / steps), units % steps
      out[#out + 1] = { tier = t.name, text = t.glyphs[steps]:rep(full) .. (t.glyphs[rest] or "") }
    end
  end
  return out
end

--- Link each tier's group to its theme group, leaving one the colourscheme or
--- user set alone; cheap enough to run per render, so no ColorScheme autocmd.
function M.define_highlights()
  for _, t in ipairs(M.TIERS) do
    vim.api.nvim_set_hl(0, t.hl, { link = t.link, default = true })
  end
end

return M
