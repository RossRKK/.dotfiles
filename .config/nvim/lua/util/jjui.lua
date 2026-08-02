local M = {}

-- The jjui float we last opened (a snacks.win). snacks keeps one terminal per
-- cmd+cwd alive; tracking the current one lets us hide whatever jjui is up (even
-- one the picker opened for another repo), mirroring lazygit.lua.
local term = nil

-- Float jjui at `cwd` (nil = nvim's cwd), with our shared window behaviour.
--
-- Snacks.terminal already runs checktime when the process *exits* (`q` in jjui),
-- but we hide the float on WinLeave rather than quitting it, so jjui stays
-- resident. jj snapshots the working copy on most commands, so a squash/rebase/
-- abandon rewrites files under open buffers; reload them each time focus leaves
-- the float too. WinLeave has no window-scoped autocmd pattern (unlike
-- WinClosed), so the callback checks nvim_get_current_win() itself.
---@param cwd? string
function M.float(cwd)
  term = Snacks.terminal.toggle("jjui", {
    cwd = cwd,
    win = {
      on_win = function(self)
        self:on("WinLeave", function()
          if vim.api.nvim_get_current_win() == self.win then
            self:hide()
            vim.schedule(function()
              vim.cmd.checktime()
            end)
          end
        end)
      end,
    },
  })
end

-- Hide the current jjui float if one is up; returns whether it did.
function M.hide()
  if term and term:win_valid() then
    term:hide()
    return true
  end
  return false
end

-- jjui for the current repo, toggled. If any jjui float is already open --
-- including one the picker opened for another repo -- close it, so this is a
-- reliable "close whatever jjui is up" for muscle memory.
function M.open()
  if M.hide() then
    return
  end
  M.float()
end

return M
