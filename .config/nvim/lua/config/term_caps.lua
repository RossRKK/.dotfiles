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
--   * Neovide isn't a terminal at all -- see the note on the check below.

local M = {}

-- Ghostty exports both of these into the environment it launches; either is a
-- sufficient positive signal (TERM_PROGRAM alone is masked to "tmux" inside a
-- multiplexer, but the main editor runs directly in the terminal here).
--
-- Neovide is excluded first, because those variables are INHERITED: `neovide`
-- launched from a Ghostty shell carries GHOSTTY_RESOURCES_DIR into a GUI that
-- draws its own grid with Skia and speaks no graphics protocol at all. Without
-- this check that instance loads image.nvim (which then renders nothing) and
-- skips open-external's image extensions, so a PNG opens as raw bytes.
-- Neovide has no inline-image support to detect: it's blocked on Neovim
-- growing a GUI-side image API (neovim/neovim#12991), so a flat `false` here
-- stays correct until that lands.
--
-- vim.g.neovide is reliable this early: Neovide runs nvim with --embed, which
-- holds startup until the UI attaches, so the global is set before init.lua.
function M.inline_images_supported()
  if vim.g.neovide then
    return false
  end
  return vim.env.TERM_PROGRAM == "ghostty" or vim.env.GHOSTTY_RESOURCES_DIR ~= nil
end

return M
