-- Telling "the clipboard holds text" from "the clipboard holds an image", and
-- reading the image (or copied files) from Windows, for the Ctrl+V mappings in
-- config/keymaps.lua and the agent chat's prompt (config/agent_chat.lua).
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

--- The clipboard's text, or nil when it holds an image or nothing.
--- @return string|nil
function M.text()
  -- pcall: Neovide's provider raises "cannot get clipboard contents" on an image.
  local ok, text = pcall(vim.fn.getreg, "+")
  if ok and M.is_text(text) then
    return text
  end
  return nil
end

--- A g:clipboard over Neovide's clipboard RPC, as Neovide's own, except that a clipboard it
--- can't read (an image) reads as empty: a put then says E353 instead of raising its error.
--- @param request fun(method: string, ...): any an RPC request to Neovide
--- @return table
function M.neovide_provider(request)
  local function get(register)
    return function()
      local ok, lines = pcall(request, "neovide.get_clipboard", register)
      return ok and lines or {}
    end
  end
  local function set(register)
    return function(lines)
      request("neovide.set_clipboard", lines, register)
    end
  end
  return {
    name = "neovide",
    copy = { ["+"] = set("+"), ["*"] = set("*") },
    paste = { ["+"] = get("+"), ["*"] = get("*") },
    cache_enabled = false,
  }
end

-- Read through interop rather than WSLg's bridge, which offers images only as
-- image/bmp and has segfaulted weston on image transfers.
local READ_WINDOWS = table.concat({
  "Add-Type -AssemblyName System.Windows.Forms;",
  "$i=[Windows.Forms.Clipboard]::GetImage();",
  "if ($i) { $ms=New-Object IO.MemoryStream;",
  "$i.Save($ms,[Drawing.Imaging.ImageFormat]::Png);",
  "'png ' + [Convert]::ToBase64String($ms.ToArray()) }",
  "else { [Windows.Forms.Clipboard]::GetFileDropList() | ForEach-Object { 'file ' + $_ } }",
}, " ")

--- @alias util.clipboard.Windows
--- | { kind: "image", png: string }
--- | { kind: "files", paths: string[] }

--- What READ_WINDOWS printed: an image's PNG bytes, or the Windows paths of files copied in Explorer.
--- @param stdout string
--- @return util.clipboard.Windows|nil
function M.parse_windows(stdout)
  local paths = {}
  for line in vim.gsplit(stdout, "\r?\n", { trimempty = true }) do
    local kind, value = line:match("^(%a+) (.+)$")
    if kind == "png" then
      return { kind = "image", png = vim.base64.decode(value) }
    elseif kind == "file" then
      paths[#paths + 1] = value
    end
  end
  return #paths > 0 and { kind = "files", paths = paths } or nil
end

--- Read the Windows clipboard's image or copied files, calling `on_read` on the main loop
--- with them (copied files as WSL paths), or nil for neither.
--- @param on_read fun(content: util.clipboard.Windows|nil)
function M.read_windows(on_read)
  vim.system({ "powershell.exe", "-NoProfile", "-Command", READ_WINDOWS }, { text = true }, function(result)
    vim.schedule(function()
      local content = result.code == 0 and M.parse_windows(result.stdout) or nil
      if content and content.kind == "files" then
        content.paths = vim.tbl_map(M.wsl_path, content.paths)
      end
      on_read(content)
    end)
  end)
end

--- Serve `png` as the Wayland clipboard's image/png, calling `on_done` once it is.
--- @param png string
--- @param on_done fun()
function M.copy_to_wayland(png, on_done)
  -- No stdout/stderr pipes: wl-copy's daemon would inherit them and hold the exit callback forever.
  vim.system({ "wl-copy", "-t", "image/png" }, { stdin = png, stdout = false, stderr = false }, function()
    vim.schedule(on_done)
  end)
end

--- The path `text` is, when it is one path and nothing else: a Linux one, or a Windows one
--- (as Explorer's "Copy as path" gives it, quoted) as WSL sees it.
--- @param text string
--- @return string|nil
function M.path_in(text)
  local path = vim.trim(text):gsub('^"(.*)"$', "%1")
  if path:find("\n") then
    return nil
  end
  if path:match("^%a:[\\/]") or path:match("^\\\\") then
    return M.wsl_path(path)
  end
  return path:match("^/") and path or nil
end

--- `path` on Windows as WSL sees it.
--- @param path string
--- @return string
function M.wsl_path(path)
  local result = vim.system({ "wslpath", "-u", path }, { text = true }):wait()
  return result.code == 0 and vim.trim(result.stdout) or path
end

return M
