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

      -- Lazygit in a floating window
      local Terminal = require("toggleterm.terminal").Terminal
      local lazygit = Terminal:new({
        cmd = "lazygit",
        direction = "float",
        float_opts = {
          border = "curved",
          width = math.floor(vim.o.columns * 0.9),
          height = math.floor(vim.o.lines * 0.9),
        },
        on_close = function()
          vim.cmd("checktime") -- reload files changed by lazygit
        end,
      })
      vim.keymap.set("n", "<leader>gg", function()
        lazygit:toggle()
      end, { desc = "Open lazygit" })

    end,
  },
}
