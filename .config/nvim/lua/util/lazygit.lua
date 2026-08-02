local M = {}

-- The lazygit float we last opened (a snacks.win). snacks keeps one terminal
-- per cwd alive; tracking the current one lets us hide whatever is up (e.g.
-- util.vcs hides both TUIs before popping the project picker).
local term = nil

-- Float lazygit at `cwd` (nil = snacks' default: the current file's repo, else
-- nvim's cwd), with our shared window behaviour.
--
-- Snacks.lazygit() auto-configures the colorscheme and runs checktime on close
-- to reload files it changed, and toggles: a second call for the same cwd hides
-- it. WinLeave hides the float rather than leaving it open behind the editor
-- when focus moves away (e.g. clicking another window); WinLeave has no
-- window-scoped autocmd pattern (unlike WinClosed), so the callback checks
-- nvim_get_current_win() itself.
---@param cwd? string
function M.float(cwd)
  term = Snacks.lazygit({
    cwd = cwd,
    win = {
      on_win = function(self)
        self:on("WinLeave", function()
          if vim.api.nvim_get_current_win() == self.win then
            self:hide()
          end
        end)
      end,
    },
  })
end

-- Hide the current lazygit float if one is up; returns whether it did.
function M.hide()
  if term and term:win_valid() then
    term:hide()
    return true
  end
  return false
end

-- lazygit for the current repo, toggled. If any lazygit float is already open --
-- including one the picker opened for another repo -- close it, so this is a
-- reliable "close whatever lazygit is up" for muscle memory.
function M.open()
  if M.hide() then
    return
  end
  M.float()
end

return M
