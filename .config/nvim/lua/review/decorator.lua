-- nvim-tree decorator: flags files (and their ancestor folders) under review.
--
--   ● (ReviewChanged)  changed on the branch, not yet triaged
--   ✓ (ReviewApproved) approved and unchanged since
--   ✗ (ReviewRejected) flagged; unchanged since it was rejected
--   ↻ (ReviewRevised)  was rejected, then edited — re-review the fix
--
-- A folder shows the highest-priority descendant status (revised > changed >
-- rejected > approved), so what needs the reviewer's attention surfaces and the
-- folder only goes ✓ once every changed descendant is approved. Only the glyph
-- is coloured; the filename is left alone.
--
-- When review mode is on, a file (or folder containing one) with PR comments
-- also gets a ✎ (ReviewCommentSign) marker, from lua/review/comments.lua.
--
-- Registered in the renderer.decorators list; see lua/plugins/explorer.lua.

---@class ReviewDecorator: nvim_tree.api.Decorator
local ReviewDecorator = require("nvim-tree.api").Decorator:extend()

function ReviewDecorator:new()
  self.enabled = true
  self.highlight_range = "none" -- colour the glyph only, never the node name
  self.icon_placement = "before" -- glyph sits just before the file name

  -- Keyed by status; not named `icons` to avoid shadowing the :icons() method.
  self.icon_by_status = {
    changed = { str = "●", hl = { "ReviewChanged" } },
    approved = { str = "✓", hl = { "ReviewApproved" } },
    rejected = { str = "✗", hl = { "ReviewRejected" } },
    revised = { str = "↻", hl = { "ReviewRevised" } },
  }
end

---@param node nvim_tree.api.Node
---@return string? "changed" | "approved" | "rejected" | "revised" | nil
local function status(node)
  local review = require("review")
  if node.type == "directory" then
    return review.folder(node.absolute_path)
  elseif node.type == "file" then
    return review.status(node.absolute_path)
  end
  return nil
end

---@param node nvim_tree.api.Node
---@return nvim_tree.api.highlighted_string[]?
function ReviewDecorator:icons(node)
  local icons = {}
  local icon = self.icon_by_status[status(node) or ""]
  if icon then
    icons[#icons + 1] = icon
  end
  if require("review.comments").has_comments(node.absolute_path) then
    icons[#icons + 1] = { str = "✎", hl = { "ReviewCommentSign" } }
  end
  return #icons > 0 and icons or nil
end

return ReviewDecorator
