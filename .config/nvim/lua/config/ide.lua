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
-- relative argv would no longer resolve to a directory).
local ide_mode = vim.fn.argc() == 1 and vim.fn.isdirectory(vim.fn.argv(0)) == 1

function M.is_ide_mode()
  return ide_mode
end

return M
