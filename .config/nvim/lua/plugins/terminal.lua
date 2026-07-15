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

      -- Tab keymaps for the side terminal (<C-b>{1-9}, etc).
      require("config.terms").setup_keymaps()
      require("config.terms").setup_exit()
      -- Show the titled tab strip when the side terminal is in play (IDE mode).
      if ide.is_ide_mode() then
        require("config.terms").enable_tabline()
      end

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
            -- Go through config.terms so slot 1 is registered as a tab.
            -- insert = false because we hand focus straight back to the editor.
            require("config.terms").show(1, { insert = false })
            vim.cmd("wincmd p")
            vim.cmd("stopinsert")
          end)
        end,
      })

      -- Focusing a terminal buffer switches it to terminal (insert) mode.
      -- vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
      --   pattern = "term://*",
      --   callback = function()
      --     vim.schedule(function()
      --       vim.cmd("startinsert")
      --     end)
      --   end,
      -- })

      -- <C-g> works from normal and terminal mode (pairs with the <C-t>
      -- side-terminal toggle) so lazygit is reachable wherever the cursor is.
      -- Snacks.lazygit() floats lazygit, auto-configured for the colorscheme, and
      -- runs checktime on close to reload files it changed; a second press hides it.
      vim.keymap.set({ "n", "t" }, "<C-g>", function()
        Snacks.lazygit()
      end, { desc = "Open lazygit" })
      -- <leader>gP (PR for the current branch) lives in git.lua with the other
      -- <leader>g git maps.
    end,
  },
}
