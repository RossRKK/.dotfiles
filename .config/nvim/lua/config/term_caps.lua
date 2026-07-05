-- Terminal graphics capability, used to decide inline vs external image opening.
--
-- Inline rendering (the kitty graphics protocol via image.nvim) is reliable in
-- Ghostty, so that's the only terminal we enable it for. Everything else opens
-- images in the OS viewer instead (see open-external.lua):
--   * Windows Terminal only speaks sixel, which can't reflow/clip through our
--     tree+terminal layout.
--   * WezTerm (over WSL) speaks the kitty protocol but its implementation is
--     partial: it can't read the Linux temp-file path image.nvim transmits, and
--     base64/unicode-placeholder fallbacks render broken. Not worth the hacks.

local M = {}

-- Ghostty exports both of these into the environment it launches; either is a
-- sufficient positive signal (TERM_PROGRAM alone is masked to "tmux" inside a
-- multiplexer, but the main editor runs directly in the terminal here).
function M.inline_images_supported()
  return vim.env.TERM_PROGRAM == "ghostty" or vim.env.GHOSTTY_RESOURCES_DIR ~= nil
end

return M
