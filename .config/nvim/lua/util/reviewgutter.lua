-- One neo-tree gutter for the branch-review glyphs (triage.nvim status,
-- nitpick.nvim comment bubble). Both plugins ship their own component, but each
-- adds two cells only to the rows it marks, which pushed those rows' names to
-- the right of their neighbours. This module instead:
--
--   * `gutter`  draws a two-cell column on every row while review mode is on
--     (triage status or a blank, then a space), and nothing at all while it is
--     off. A commented row alone grows by one cell so the bubble fits between
--     the status and the space: a comment always comes with a status, so
--     unmarked and status-only rows keep the same spacing.
--   * `icon`    wraps neo-tree's icon component and drops its trailing pad while
--     review mode is on, so the gutter reuses that cell and the tree grows by one
--     cell, not two.
--
-- Pure: the plugin objects are required lazily so tests can fake them.

local M = {}

-- U+F075, the nerd-font speech bubble (fa-comment), written as bytes so the glyph
-- can't be lost in transit when the file is edited.
M.bubble = "\xef\x81\xb5"

local function enabled()
  local ok, triage = pcall(require, "triage")
  return ok and triage.is_enabled() or false
end

--- neo-tree renderer component: the review gutter for a node.
---@return table chunk|table[] chunks
function M.gutter(_, node, _)
  if not enabled() then
    return { text = "" }
  end
  local triage = require("triage")
  local status = node.type == "directory" and triage.folder(node.path) or triage.status(node.path)
  local spec = status and triage.icons[status]
  local ok, nitpick = pcall(require, "nitpick")
  local commented = ok and nitpick.has_comments(node.path)
  -- neo-tree takes one highlight per chunk, so the gutter is a list of chunks:
  -- the status cell, the bubble cell only when there is a comment, then the pad.
  local chunks = { spec and { text = spec.text, highlight = spec.hl } or { text = " " } }
  if commented then
    chunks[#chunks + 1] = { text = M.bubble, highlight = "ReviewCommentTreeIcon" }
  end
  chunks[#chunks + 1] = { text = " " }
  return chunks
end

--- neo-tree renderer component: the stock icon, minus its trailing pad while the
--- gutter is showing.
---@return table chunk
function M.icon(config, node, state)
  local chunk = require("neo-tree.sources.common.components").icon(config, node, state)
  if enabled() and type(chunk.text) == "string" then
    chunk.text = chunk.text:gsub(" $", "")
  end
  return chunk
end

return M
