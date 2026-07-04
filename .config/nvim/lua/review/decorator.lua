-- nvim-tree decorator: flags files (and their ancestor folders) under review.
--
--   ● (ReviewChanged)  changed since the merge-base, not yet reviewed
--   ✓ (ReviewReviewed) reviewed and unchanged since
--
-- A folder shows ● while any changed descendant is still unreviewed, and ✓ once
-- they're all reviewed. Only the glyph is coloured; the filename is left alone.
--
-- Registered in the renderer.decorators list; see lua/plugins/explorer.lua.

---@class ReviewDecorator: nvim_tree.api.Decorator
local ReviewDecorator = require("nvim-tree.api").Decorator:extend()

function ReviewDecorator:new()
  self.enabled = true
  self.highlight_range = "none" -- colour the glyph only, never the node name
  self.icon_placement = "after"

  self.icon_changed = { str = "●", hl = { "ReviewChanged" } }
  self.icon_reviewed = { str = "✓", hl = { "ReviewReviewed" } }
end

---@param node nvim_tree.api.Node
---@return string? "changed" | "reviewed" | nil
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
  local s = status(node)
  if s == "reviewed" then
    return { self.icon_reviewed }
  elseif s == "changed" then
    return { self.icon_changed }
  end
  return nil
end

return ReviewDecorator
