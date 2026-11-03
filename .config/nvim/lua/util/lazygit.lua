local M = {}

-- The lazygit float we last opened (a snacks.win). snacks keeps one terminal
-- per cwd alive; tracking the current one lets us hide whatever is up (e.g.
-- before popping the project picker).
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
      -- Buffer-local: lazygit is a terminal, and the global <C-g> is normal-mode only.
      keys = { hide_lazygit = { "<C-g>", "hide", mode = "t" } },
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

-- lazygit's <c-b> on a commit (config.yml): review `root` against that commit.
-- Returns "" because --remote-expr needs a value back.
---@param sha string
---@param root string the repo lazygit is in, which may not be nvim's cwd
---@return string
function M.set_review_base(sha, root)
  M.hide()
  require("triage").set_target(sha, root)
  return ""
end

-- <C-S-g>: pick a project and open lazygit there, for driving a repo other than
-- nvim's cwd (e.g. within a polyrepo tree).
function M.pick()
  -- Hide any open float first: WinLeave doesn't reliably fire when the picker
  -- grabs focus, so an existing lazygit would otherwise linger over the picker.
  M.hide()
  Snacks.picker.projects({
    confirm = function(picker, item)
      picker:close()
      if item and item.file then
        -- schedule so the picker window is fully torn down before the lazygit
        -- terminal float takes focus.
        vim.schedule(function()
          M.float(item.file)
        end)
      end
    end,
  })
end

return M
