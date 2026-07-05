-- Terminal graphics capability, used to decide inline vs external image opening.
--
-- Inline rendering (the kitty graphics protocol via image.nvim) is reliable in
-- Ghostty and WezTerm. Windows Terminal only speaks sixel, which can't reflow or
-- clip when our tree/side-terminal layout shifts around it, so there we open
-- images in the OS viewer instead (see open-external.lua).

local M = {}

-- Each terminal exports its own marker env var; either the TERM_PROGRAM name or
-- the terminal-specific var is a sufficient positive signal. TERM_PROGRAM alone
-- is masked to "tmux" inside a multiplexer, but the main editor runs directly in
-- the terminal here, and the *_EXECUTABLE/RESOURCES vars survive that anyway.
function M.inline_images_supported()
  return vim.env.TERM_PROGRAM == "ghostty"
    or vim.env.GHOSTTY_RESOURCES_DIR ~= nil
    or vim.env.TERM_PROGRAM == "WezTerm"
    or vim.env.WEZTERM_EXECUTABLE ~= nil
end

return M
