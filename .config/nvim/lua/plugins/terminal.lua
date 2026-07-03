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
        -- Applies to whichever terminal actually opens (incl. the <C-t> side
        -- terminal, which is created fresh from this global config).
        on_open = function(term)
          if term.direction == "vertical" then
            vim.wo[term.window].winfixwidth = true -- keep the side terminal fixed at 80
            -- The side terminal is full-height (nothing above it), so <C-k> nav
            -- is useless here; pass it through to the running app (e.g. Claude Code).
            vim.keymap.set("t", "<C-k>", "<C-k>", { buffer = term.bufnr })
          end
        end,
      })

      -- Open the vertical side terminal automatically on startup, then hand
      -- focus back to the editor window so we land on the file/tree, not the term.
      vim.api.nvim_create_autocmd("VimEnter", {
        callback = function()
          vim.schedule(function()
            require("toggleterm").toggle(1, 80, nil, "vertical")
            vim.cmd("wincmd p")
          end)
        end,
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

      -- Keep the vertical side terminal fixed at 80. winfixwidth only blocks
      -- automatic equalization, not the explicit resizes nvim-tree does on open,
      -- so re-assert the width whenever the layout changes.
      local enforcing_term_width = false
      vim.api.nvim_create_autocmd("WinResized", {
        callback = function()
          if enforcing_term_width then
            return
          end
          enforcing_term_width = true
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            local buf = vim.api.nvim_win_get_buf(win)
            local floating = vim.api.nvim_win_get_config(win).relative ~= ""
            if vim.bo[buf].filetype == "toggleterm" and not floating and vim.api.nvim_win_get_width(win) ~= 80 then
              vim.api.nvim_win_set_width(win, 80)
            end
          end
          enforcing_term_width = false
        end,
      })

      local Terminal = require("toggleterm.terminal").Terminal

      -- Lazygit on a dedicated id so <C-t> (terminal #1) never toggles it.
      local lazygit = Terminal:new({
        cmd = "lazygit",
        count = 99,
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
