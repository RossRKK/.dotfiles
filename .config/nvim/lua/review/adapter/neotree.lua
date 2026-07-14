-- neo-tree adapter for the review UI.
--
-- All of the review plugin's coupling to a specific file explorer lives behind
-- this interface (see review/adapter/init.lua, which selects the active one):
--
--   status_component(config, node, state) -> chunk[]   a neo-tree renderer
--     component that draws the ●/✓/✗/↻ triage glyph (and a speech-bubble comment
--     marker) before a node's name. Coloured glyph only; the name is left alone.
--   cursor_path() -> string?   absolute path of the node under the cursor when
--     the explorer is focused, else nil (so callers fall back to the buffer).
--   redraw()   repaint the explorer so the component picks up new status.
--
-- To port the review UI to another explorer, write a sibling module exposing the
-- same three and re-point review/adapter/init.lua at it.

local M = {}

-- Status -> glyph + highlight. The trailing space separates the glyph from the
-- filename that follows it in the renderer. Highlights are defined in
-- review/init.lua's set_hl (themeable, glyph-only colouring).
local icon_by_status = {
  changed = { text = "● ", highlight = "ReviewChanged" },
  approved = { text = "✓ ", highlight = "ReviewApproved" },
  rejected = { text = "✗ ", highlight = "ReviewRejected" },
  revised = { text = "↻ ", highlight = "ReviewRevised" },
}

--- A neo-tree renderer component: the triage glyph plus a speech bubble when the path has PR
--- comments or drafts. Directories show their rolled-up descendant status. Placed
--- before "name" in the file/directory renderers (see plugins/explorer.lua).
---@return table chunk, or a list of chunks
function M.status_component(_, node, _)
  local review = require("review")
  local status = node.type == "directory" and review.folder(node.path) or review.status(node.path)

  local chunks = {}
  local icon = status and icon_by_status[status]
  if icon then
    chunks[#chunks + 1] = icon
  end
  if require("review.comments").has_comments(node.path) then
    -- "\xef\x81\xb5" is U+F075, the nerd-font speech bubble (fa-comment); written
    -- as bytes so the glyph can't be lost in transit when the file is edited.
    chunks[#chunks + 1] = { text = "\xef\x81\xb5 ", highlight = "ReviewCommentTreeIcon" }
  end

  -- neo-tree renders a single chunk or a list of them; empty text is a no-op.
  if #chunks == 0 then
    return { text = "" }
  end
  return chunks
end

--- Absolute path of the node under the cursor, but only while the filesystem
--- explorer is the focused window — otherwise nil, so the caller uses the current
--- buffer instead. neo-tree buffers carry the "neo-tree" filetype.
---@return string?
function M.cursor_path()
  if vim.bo.filetype ~= "neo-tree" then
    return nil
  end
  local ok, manager = pcall(require, "neo-tree.sources.manager")
  if not ok then
    return nil
  end
  local state = manager.get_state("filesystem")
  if not state or not state.tree then
    return nil
  end
  local node = state.tree:get_node()
  return node and node.path or nil
end

--- Repaint the filesystem explorer so the review component re-runs. Safe to call
--- when neo-tree isn't loaded or no tree is open.
function M.redraw()
  local ok, manager = pcall(require, "neo-tree.sources.manager")
  if ok then
    pcall(manager.refresh, "filesystem")
  end
end

return M
