return {
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    ---@type snacks.Config
    opts = {
      -- terminal and lazygit are on-demand modules (no `enabled` needed). Add
      -- other snacks modules here as they get adopted.
    },
    config = function(_, opts)
      require("snacks").setup(opts)

      -- fishmonger owns its own default width; edgy (see edgy.lua) adopts the
      -- window via the "fishmonger" filetype and re-governs sizing in this config.
      -- shell: bare "fish" (jobstart resolves it via $PATH) rather than a
      -- hardcoded path, so this works whether fish lives at /usr/bin,
      -- /opt/homebrew/bin, or elsewhere.
      -- project_name: fishmonger's own default is the tabpage cwd's basename,
      -- which is the same answer everywhere except a worktree; config.workspace
      -- is the one place that names a workspace, so the agent view borrows it
      -- rather than growing a second naming rule.
      require("fishmonger").setup({
        shell = "fish",
        project_name = function(tab)
          return require("config.workspace").name(tab)
        end,
      })
      -- Tab keymaps for the side terminal (<C-b>{1-9}, etc).
      require("fishmonger").setup_keymaps()
      require("fishmonger").setup_exit()

      -- The side terminal auto-opens as part of a workspace (IDE mode, and every
      -- <leader>tn project tabpage) -- config.workspace.open does it, so there is
      -- one place that knows the layout. Text-editor mode (single file, bare
      -- nvim, commit message) opens nothing; <C-t> summons it anywhere.

      -- <C-g> works from normal and terminal mode (pairs with the <C-t>
      -- side-terminal toggle) so the git TUI is reachable wherever the cursor
      -- is; a second press hides it. It dispatches on the repo under the cursor:
      -- jjui in a jj repo, lazygit otherwise (see util.vcs). A leader map can't
      -- serve here -- <space> in a terminal would stutter waiting for the chord,
      -- breaking legitimate space presses -- so the git TUI stays on a ctrl key.
      -- <C-S-g> instead pops a project picker to drive a repo other than nvim's
      -- cwd (e.g. within a polyrepo tree), dispatching per chosen repo.
      vim.keymap.set({ "n", "t" }, "<C-g>", function()
        require("util.vcs").open()
      end, { desc = "Open git TUI (lazygit / jjui)" })
      vim.keymap.set({ "n", "t" }, "<C-S-g>", function()
        require("util.vcs").pick()
      end, { desc = "Open git TUI in a picked project" })
      -- <leader>gP (PR for the current branch) lives in git.lua with the other
      -- <leader>g git maps.
    end,
  },
}
