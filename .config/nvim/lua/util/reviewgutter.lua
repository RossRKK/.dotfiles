-- One neo-tree gutter for the branch-review glyphs (triage.nvim status,
-- nitpick.nvim comment bubble). Both plugins ship their own component, but each
-- adds two cells only to the rows it marks, which pushed those rows' names to
-- the right of their neighbours. This module instead:
--
--   * `gutter`  draws a fixed two-cell column on every row while review mode is
--     on (glyph + space, or two blanks), and nothing at all while it is off. The
--     comment bubble wins over the triage status when a row has both.
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
---@return table chunk
function M.gutter(_, node, _)
  if not enabled() then
    return { text = "" }
  end
  local ok, nitpick = pcall(require, "nitpick")
  if ok and nitpick.has_comments(node.path) then
    return { text = M.bubble .. " ", highlight = "ReviewCommentTreeIcon" }
  end
  local triage = require("triage")
  local status = node.type == "directory" and triage.folder(node.path) or triage.status(node.path)
  local spec = status and triage.icons[status]
  if spec then
    return { text = spec.text .. " ", highlight = spec.hl }
  end
  return { text = "  " }
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
