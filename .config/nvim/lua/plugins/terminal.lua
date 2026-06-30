return {
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    config = function()
      require("toggleterm").setup({
        direction = "vertical",
        size = function(term)
          if term.direction == "vertical" then
            return 80
          end
        end,
        open_mapping = [[<C-t>]],
        hide_numbers = true,
        shade_terminals = false,
        start_in_insert = true,
        shell = "tmux new-session -A -s neovim",
      })

      -- Auto enter insert mode when focusing a terminal buffer
      vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
        pattern = "term://*",
        callback = function()
          vim.schedule(function()
            vim.cmd("startinsert")
          end)
        end,
      })

      local current = 1
      local max_terms = 5

      vim.keymap.set({ "n", "t" }, "<C-PageDown>", function()
        current = (current % max_terms) + 1
        require("toggleterm").toggle(current, nil, nil, "vertical")
      end, { desc = "Next terminal" })

      vim.keymap.set({ "n", "t" }, "<C-PageUp>", function()
        current = ((current - 2) % max_terms) + 1
        require("toggleterm").toggle(current, nil, nil, "vertical")
      end, { desc = "Prev terminal" })
    end,
  },
}
