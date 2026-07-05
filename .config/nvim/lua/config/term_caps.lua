-- Terminal graphics capability, used to decide inline vs external image opening.
--
-- Inline rendering (the kitty graphics protocol via image.nvim) is reliable in
-- Ghostty. Windows Terminal only speaks sixel, which can't reflow or clip when
-- our tree/side-terminal layout shifts around it, so there we open images in the
-- OS viewer instead (see open-external.lua).

local M = {}

-- Ghostty exports both of these into the environment it launches; either is a
-- sufficient positive signal (TERM_PROGRAM alone is masked to "tmux" inside a
-- multiplexer, but the main editor runs directly in the terminal here).
function M.inline_images_supported()
  return vim.env.TERM_PROGRAM == "ghostty" or vim.env.GHOSTTY_RESOURCES_DIR ~= nil
end

return M
