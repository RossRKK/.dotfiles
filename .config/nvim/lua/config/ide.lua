-- Single source of truth for "IDE mode" vs "text-editor mode" and the window
-- geometry that follows from it.
--
-- IDE mode  = launched with a single directory argument (`nvim .`, `nvim ~/proj`).
--             Explorer + side terminal auto-open.
-- Text mode = anything else: a single file, bare `nvim`, `nvim` invoked for a
--             commit message or an edit prompt. Nothing auto-opens; every panel
--             is still reachable manually (<C-t>, <leader>e, <C-g>).
--
-- Detection reads argv directly (not cwd), so it's valid from the very first
-- VimEnter regardless of which plugin's handler runs first.

local M = {}

-- The side terminal never drops below 80 columns (enough for console output and
-- Claude Code). If that crowds the code, toggle it off (<C-t>) and the buffer
-- reclaims the whole remaining area.
M.min_term_width = 80

-- Captured once at module load, which happens during startup plugin config —
-- before explorer.lua's VimEnter `cd`s into the directory (after which the
-- relative argv would no longer resolve to a directory).
local ide_mode = vim.fn.argc() == 1 and vim.fn.isdirectory(vim.fn.argv(0)) == 1

function M.is_ide_mode()
  return ide_mode
end

-- Width the explorer currently occupies, measured from its live window (0 if
-- it's closed). Read at runtime rather than hardcoded so explorer.lua stays the
-- single owner of the tree width.
function M.tree_width()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "NvimTree" then
      -- +1 for the window separator column the tree costs the rest of the layout.
      return vim.api.nvim_win_get_width(win) + 1
    end
  end
  return 0
end

-- Target width for the side terminal: 40% of the region after the explorer,
-- floored at min_term_width. The 60:40 bias toward the buffer keeps the code
-- (the thing you're mostly reading) wider. Small laptop screens still pin the
-- terminal at 80 and let the buffer take the rest.
M.term_fraction = 0.4

function M.term_width()
  local available = vim.o.columns - M.tree_width()
  return math.max(M.min_term_width, math.floor(available * M.term_fraction))
end

return M
