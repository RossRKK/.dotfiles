-- Telling "the clipboard holds text" from "the clipboard holds an image", for
-- the terminal-mode paste mapping in config/keymaps.lua.
--
-- This can't be inferred from whether `getreg("+")` errors. Whether it does is
-- a property of the *provider*, not of the clipboard: win32yank rejects image
-- data ("clipboard provider gave invalid data"), while bare `wl-paste` returns
-- text/plain only if the source offers it and otherwise dumps the raw bytes of
-- the first type it finds -- so a screenshot arrives as a perfectly successful
-- getreg full of PNG.
--
-- Nor can it be a NUL scan, the obvious way to spot binary: a Vim register
-- cannot hold a NUL, and the register representation rewrites each one to NL.
-- A PNG header reaches us as "<89>PNG\r\n\26\n\n\n\n\rIHDR" -- the \0\0\0\13
-- IHDR length is already three newlines by the time any Lua sees it. Sniffing
-- has to work on what survives that, which means magic numbers.
local M = {}

-- Leading bytes of the formats a clipboard actually offers as an image. All are
-- NUL-free, so they arrive intact.
local IMAGE_MAGIC = {
  "\137PNG\r\n\26\n", -- png
  "\255\216\255", -- jpeg
  "GIF87a",
  "GIF89a",
  "BM", -- bmp (WSLg and X11 hand these out in preference to png)
  "RIFF", -- webp (bytes 8..11 are "WEBP"; the RIFF prefix is enough here)
}

-- Backstop for anything not in that list. Text does not contain C0 control
-- codes other than tab/newline/carriage-return; ESC is excluded too, since
-- copied terminal output legitimately carries ANSI escapes.
local BINARY_CONTROL = "[\1-\8\11\12\14-\26\28-\31]"

-- The answer is always settled by the first few hundred bytes, and a clipboard
-- can hold megabytes.
local SNIFF_BYTES = 1024

--- Does this register content look like text a terminal should receive?
--- @param s string|nil
--- @return boolean
function M.is_text(s)
  if type(s) ~= "string" or s == "" then
    return false
  end
  for _, magic in ipairs(IMAGE_MAGIC) do
    if s:sub(1, #magic) == magic then
      return false
    end
  end
  return not s:sub(1, SNIFF_BYTES):find(BINARY_CONTROL)
end

return M
