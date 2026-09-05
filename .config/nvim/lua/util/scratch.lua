-- The scratch pad: one real file per workspace, in the system temp directory.
--
-- A real file rather than an in-memory scratch buffer, so the shell in the side
-- terminal can reach it -- `jq . "$TMPDIR/nvim-scratch/ionics.md"`, or piping it
-- into anything that reads a file. That only holds if what's on disk matches
-- what's on screen, so the buffer autosaves (see attach below) rather than
-- waiting for a :w. It opens in the main editor window like any other file: a
-- float can't be split, diffed, or sent through the usual keymaps.

local M = {}

--- The directory the scratch files live in: $TMPDIR (else /tmp) -- the same name
--- the shell knows it by, so a path read off the statusline can be typed there.
---@return string
function M.dir()
  local tmp = vim.env.TMPDIR
  if not tmp or tmp == "" then
    tmp = "/tmp"
  end
  return vim.fs.normalize(tmp) .. "/nvim-scratch"
end

--- The scratch filename for the workspace called `name`. Named after the
--- project, not a hash of its path, because the whole point is that you can
--- type it in a shell -- so two checkouts whose directories share a basename
--- share a scratch file (worktrees don't: theirs is named for the branch).
--- Markdown by default, and it costs nothing to change: the file is real, so
--- the filetype follows the extension and another format is a `:saveas`.
---@param name string workspace name (config.workspace.name)
---@return string
function M.filename(name)
  -- The name is a directory basename, so this is about spaces and the odd ':'
  -- rather than about safety -- but it also rules out '/' and '..' by leaving
  -- nothing but word characters, '-' and '_'.
  local slug = (name:gsub("[^%w_%-]", "-"))
  if slug:match("^%-*$") then
    slug = "scratch"
  end
  return slug .. ".md"
end

--- Absolute path of a workspace's scratch file.
---@param tab? integer tabpage handle (default: current)
---@return string
function M.path(tab)
  return M.dir() .. "/" .. M.filename(require("config.workspace").name(tab))
end

-- Autosave, so a pipe from the terminal never reads a stale note. Not on every
-- keystroke: TextChanged catches a normal-mode edit, InsertLeave the end of an
-- insert, and BufLeave walking away mid-insert -- which covers everything short
-- of piping the file while still typing into it. Not cleared on create: the
-- group holds one buffer-local autocmd per workspace's scratch buffer.
local group = vim.api.nvim_create_augroup("scratch_autosave", { clear = false })

--- Mark a scratch buffer as one, and keep it written to disk.
---@param buf integer
local function attach(buf)
  if vim.b[buf].scratch_root then
    return
  end
  -- Which workspace's scratch this is. The file lives outside every project, so
  -- without this the bufferline filter (plugins/buffers.lua) would either hide
  -- it everywhere or show every project's on every project's bar.
  vim.b[buf].scratch_root = vim.fs.normalize(require("config.workspace").cwd())
  -- Autosave + format-on-save would reflow a half-typed note under the cursor
  -- (markdown goes through prettierd, see plugins/conform.lua), so this buffer
  -- opts out. :FormatEnable turns it back on for a note worth tidying.
  vim.b[buf].disable_autoformat = true
  -- Nothing to recover: the file is written as it's typed, so a leftover swap
  -- file could only ever be older than what's on disk -- and it would prompt on
  -- every open after a crash.
  vim.bo[buf].swapfile = false
  vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave", "BufLeave" }, {
    group = group,
    buffer = buf,
    desc = "Write the scratch file so the shell sees it",
    callback = function()
      if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modified then
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("silent! write")
        end)
      end
    end,
  })
end

-- Every way into a scratch file, not just M.open below: the picker opens one with
-- a plain :edit, and so does a hand-typed path. Registered when this module is
-- first required, which every one of those goes through.
vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
  group = group,
  pattern = M.dir() .. "/*",
  desc = "Set a scratch file's buffer up as one",
  callback = function(ev)
    attach(ev.buf)
  end,
})

--- Open this workspace's scratch file in the main editor window.
function M.open()
  local dir = M.dir()
  local ok, err = pcall(vim.fn.mkdir, dir, "p")
  if not ok then
    vim.notify("scratch: can't create " .. dir .. ": " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  require("config.windows").goto_main_window()
  vim.cmd("edit " .. vim.fn.fnameescape(M.path()))
  attach(vim.api.nvim_get_current_buf())
end

--- Toggle: to the scratch file and back. "Back" is the alternate buffer, so a
--- second press returns the main window to what it was showing -- as close as a
--- real buffer gets to dismissing a float. From the terminal or the explorer
--- it's always the way in, since the scratch is never the buffer you're on.
function M.toggle()
  if vim.fs.normalize(vim.api.nvim_buf_get_name(0)) ~= M.path() then
    M.open()
    return
  end
  local alt = vim.fn.bufnr("#")
  if alt ~= -1 and vim.api.nvim_buf_is_valid(alt) and vim.bo[alt].buflisted then
    vim.cmd("buffer #")
  end
end

--- Pick among all the scratch files -- this workspace's, the other projects',
--- and any left from an earlier session -- opening in the main editor window.
function M.pick()
  local dir = M.dir()
  if vim.fn.isdirectory(dir) == 0 then
    vim.notify("no scratch files yet", vim.log.levels.INFO)
    return
  end
  -- Routed before the picker opens: snacks edits into the window the picker was
  -- opened from, which must not be the terminal or the explorer.
  require("config.windows").goto_main_window()
  require("snacks").picker.files({ cwd = dir })
end

return M
