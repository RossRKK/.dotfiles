-- The active explorer adapter. This is the single seam between the review
-- plugin's explorer-agnostic core (review/init.lua, review/comments.lua) and the
-- file explorer that draws its triage glyphs.
--
-- To port the review UI to a different explorer, write a sibling module in this
-- directory exposing the same interface (status_component / cursor_path / redraw;
-- see review/adapter/neotree.lua) and re-point this require at it.
return require("review.adapter.neotree")
