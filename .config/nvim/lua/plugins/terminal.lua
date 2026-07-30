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

      local ide = require("config.ide")

      -- fishmonger owns its own default width; edgy (see edgy.lua) adopts the
      -- window via the "fishmonger" filetype and re-governs sizing in this config.
      -- shell: bare "fish" (jobstart resolves it via $PATH) rather than a
      -- hardcoded path, so this works whether fish lives at /usr/bin,
      -- /opt/homebrew/bin, or elsewhere.
      require("fishmonger").setup({ shell = "fish" })
      -- Tab keymaps for the side terminal (<C-b>{1-9}, etc).
      require("fishmonger").setup_keymaps()
      require("fishmonger").setup_exit()

      -- IDE mode (opened a directory) auto-opens the side terminal, then hands
      -- focus back to the editor window so we land on the file/tree, not the term.
      -- Text-editor mode (single file, bare nvim, commit message) opens nothing;
      -- <C-t> is always available to summon it manually.
      vim.api.nvim_create_autocmd("VimEnter", {
        callback = function()
          if not ide.is_ide_mode() then
            return
          end
          vim.schedule(function()
            -- Go through fishmonger so slot 1 is registered as a tab.
            -- insert = false because we hand focus straight back to the editor.
            require("fishmonger").show(1, { insert = false })
            vim.cmd("wincmd p")
            vim.cmd("stopinsert")
          end)
        end,
      })

      -- <C-g> works from normal and terminal mode (pairs with the <C-t>
      -- side-terminal toggle) so lazygit is reachable wherever the cursor is;
      -- a second press hides it. <C-S-g> instead pops a project picker to drive
      -- a repo other than nvim's cwd (e.g. within a polyrepo tree).
      vim.keymap.set({ "n", "t" }, "<C-g>", function()
        require("util.lazygit").open()
      end, { desc = "Open lazygit (current repo)" })
      vim.keymap.set({ "n", "t" }, "<C-S-g>", function()
        require("util.lazygit").pick()
      end, { desc = "Open lazygit in a picked project" })
      -- <leader>gP (PR for the current branch) lives in git.lua with the other
      -- <leader>g git maps.
    end,
  },
}
