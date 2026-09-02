-- Make manual resizes of edgy panels stick.
--
-- edgy re-applies each panel's configured size on every layout pass, so a
-- mouse drag or :vertical resize snaps straight back. edgy does honour a
-- per-window override (w:edgy_width / w:edgy_height): its own resize keys
-- write it, and the edgebar uses it in place of the view's size. This module
-- writes that override whenever a panel's size changes from OUTSIDE edgy.
--
-- Telling the two apart needs care. edgy runs its own layout work under
-- eventignore=all, but that does NOT silence WinResized: Neovim queues the
-- event and delivers it later, at a safe point, and checks eventignore only
-- then -- after edgy has restored it. So edgy's own resizes do reach us,
-- deferred. Two guards make them harmless:
--
--   * A window whose size equals edgy's own target for it is skipped. After a
--     synchronous relayout the window is at target by the time the deferred
--     event arrives, even if it passed through a half-screen `wincmd H` on
--     the way.
--   * An animation frame is skipped. Each frame is a resize that fires a
--     deferred event with the window part-way to its target; pinning one
--     would freeze the panel mid-flight. edgy keeps the animated value per
--     window in edgy.animate.state and sets the window to exactly that, so a
--     window whose size equals it is a frame. A resize from outside (neo-tree
--     expanding while edgy is still animating, say) matches neither the
--     target nor the frame value, and is pinned -- with the animated value
--     snapped to it, so edgy does not glide there from the stale value.
--
-- Note the edgebar `size` in edgy's options is a MINIMUM, not the opening
-- size: the bar is max(edgebar size, each window's override or view size).
-- So the opening size belongs on the view (`size = { width = 35 }`) and the
-- edgebar size sets how far a panel may be shrunk.
local M = {}

--- Record the current size of every edgy-managed window in `wins` as its edgy
--- override. Only the bar's thin dimension is pinned (width for a side bar):
--- the long dimension is shared between stacked views and stays edgy's.
---@param wins integer[]
---@return integer[] pinned the windows whose override was written
function M.pin(wins)
  local cache = require("edgy.window").cache
  local anim = require("edgy.animate").state
  local pinned = {}
  for _, win in ipairs(wins) do
    local ewin = cache[win]
    if ewin and vim.api.nvim_win_is_valid(win) then
      local dim = ewin.view.edgebar.vertical and "width" or "height"
      local size = vim.api["nvim_win_get_" .. dim](win)
      local frame = anim[ewin] and math.floor(anim[ewin][dim] + 0.5)
      -- size 1 is edgy's parking size for a collapsed panel, never a choice.
      if size > 1 and size ~= ewin[dim] and size ~= frame then
        vim.w[win]["edgy_" .. dim] = size
        if anim[ewin] then
          anim[ewin][dim] = size
        end
        pinned[#pinned + 1] = win
      end
    end
  end
  return pinned
end

--- Forget every override so panels return to their view sizes.
function M.reset()
  require("edgy.layout").foreach({ "left", "right", "bottom", "top" }, function(edgebar)
    edgebar:equalize()
  end)
end

--- Install the WinResized hook. Must run BEFORE require("edgy").setup(): edgy
--- registers its own WinResized handler there, and autocmds fire in creation
--- order. If edgy's ran first it would snap the panel back before we read it.
function M.setup()
  vim.api.nvim_create_autocmd("WinResized", {
    group = vim.api.nvim_create_augroup("edgy_pin", { clear = true }),
    callback = function()
      M.pin(vim.v.event.windows or {})
    end,
  })
end

return M
