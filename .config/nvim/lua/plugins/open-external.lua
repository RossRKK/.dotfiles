-- Open opaque, non-text file types in the OS default application instead of
-- loading their bytes into a buffer, matched by an explicit extension list.
-- Transparent and predictable: if a format opens as garbage, add its extension
-- here. Images are intentionally absent -- image.nvim renders those inline.
--
-- vim.ui.open (Neovim 0.10+) picks the opener per platform: xdg-open (Linux),
-- open (macOS), explorer.exe / wslview (WSL), start (native Windows).
--
-- This file registers autocmds/keymaps and returns an empty spec; lazy.nvim
-- runs the top-level code when it imports the plugins directory at startup.

local group = vim.api.nvim_create_augroup("open_external", { clear = true })

local extensions = {
  "pdf",
  "doc", "docx", "odt", "rtf",
  "xls", "xlsx", "ods",
  "ppt", "pptx", "odp",
  "mp4", "mkv", "webm", "mov", "avi",
  "mp3", "wav", "flac", "ogg", "m4a",
  "zip", "7z", "rar",
}

-- Hand a path to the OS default app and report failures.
local function open_external(path)
  local _, err = vim.ui.open(path)
  if err then
    vim.notify(("open-external: %s"):format(err), vim.log.levels.ERROR)
  end
end

-- BufReadCmd fires only for the matched extensions, so it never intercepts text
-- files (no native-read reimplementation needed) and stops the bytes before
-- they ever load into the buffer.
vim.api.nvim_create_autocmd("BufReadCmd", {
  group = group,
  pattern = vim.tbl_map(function(ext)
    return "*." .. ext
  end, extensions),
  callback = function(ev)
    local path = vim.fn.fnamemodify(ev.file, ":p")
    -- The buffer nvim is opening for us (before any window switches to it).
    local alt = vim.fn.bufnr("#")
    open_external(path)
    vim.schedule(function()
      -- Put the window back on the buffer we came from, so opening a binary
      -- never disturbs your current buffer/layout...
      if alt ~= -1 and alt ~= ev.buf and vim.api.nvim_buf_is_valid(alt) then
        for _, win in ipairs(vim.fn.win_findbuf(ev.buf)) do
          vim.api.nvim_win_set_buf(win, alt)
        end
      end
      -- ...then drop only the throwaway buffer (now hidden, so no window/tab
      -- closes). unload keeps it out of the way if it can't be deleted.
      if vim.api.nvim_buf_is_valid(ev.buf) then
        pcall(vim.api.nvim_buf_delete, ev.buf, { force = true })
      end
    end)
  end,
})

return {}
