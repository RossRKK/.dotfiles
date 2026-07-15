-- Single source of truth for "IDE mode" vs "text-editor mode".
--
-- IDE mode  = launched with a single directory argument (`nvim .`, `nvim ~/proj`).
--             Explorer + side terminal auto-open.
-- Text mode = anything else: a single file, bare `nvim`, `nvim` invoked for a
--             commit message or an edit prompt. Nothing auto-opens; every panel
--             is still reachable manually (<C-t>, <leader>e, <C-g>).
--
-- Detection reads argv directly (not cwd), so it's valid from the very first
-- VimEnter regardless of which plugin's handler runs first.
--
-- Window geometry (edge placement and sizing) is owned by edgy; see
-- lua/plugins/edgy.lua.

local M = {}

-- Captured once at module load, which happens during startup plugin config —
-- before explorer.lua's VimEnter `cd`s into the directory (after which the
-- relative argv would no longer resolve to a directory). The absolute form is
-- resolved at the same instant for the same reason. This is the single place
-- that inspects argv: everything else (explorer auto-open, venv discovery)
-- asks this module.
local arg = vim.fn.argv(0)
local ide_dir = (vim.fn.argc() == 1 and type(arg) == "string" and vim.fn.isdirectory(arg) == 1)
    and vim.fn.fnamemodify(arg, ":p")
  or nil

function M.is_ide_mode()
  return ide_dir ~= nil
end

--- The directory nvim was opened on (absolute), or nil outside IDE mode.
---@return string?
function M.dir()
  return ide_dir
end

return M
