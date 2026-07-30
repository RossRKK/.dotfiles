local M = {}

-- The lazygit float we last opened (a snacks.win). snacks keeps one terminal
-- per cwd alive; tracking the current one lets the picker hide it before it
-- opens (see M.pick).
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
local function float(cwd)
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

-- <C-g>: lazygit for the current repo, toggled. If any lazygit float is already
-- open -- including one the <C-S-g> picker opened for another repo -- close it,
-- so <C-g> is a reliable "close whatever lazygit is up" for muscle memory.
function M.open()
  if term and term:win_valid() then
    term:hide()
    return
  end
  float()
end

-- <C-S-g>: pick a project (~/dev subdirs + recent git roots) and open lazygit
-- there, for driving a repo other than nvim's cwd -- e.g. picking between the
-- repos in a polyrepo tree.
function M.pick()
  -- Hide any open float first: WinLeave doesn't reliably fire when the picker
  -- grabs focus, so an existing lazygit would otherwise linger over the picker.
  if term and term:win_valid() then
    term:hide()
  end
  Snacks.picker.projects({
    confirm = function(picker, item)
      picker:close()
      if item and item.file then
        -- schedule so the picker window is fully torn down before the lazygit
        -- terminal float takes focus.
        vim.schedule(function()
          float(item.file)
        end)
      end
    end,
  })
end

return M
