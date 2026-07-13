return {
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    config = function()
      local ide = require("config.ide")

      require("toggleterm").setup({
        direction = "vertical",
        size = function(term)
          if term.direction == "vertical" then
            return ide.term_width()
          end
        end,
        hide_numbers = true,
        shade_terminals = false,
        start_in_insert = true,
        -- Applies to whichever terminal actually opens (incl. the <C-t> side
        -- terminal, which is created fresh from this global config).
        on_open = function(term)
          if term.direction == "vertical" then
            -- winfixwidth keeps auto-equalization from collapsing the terminal to
            -- an even split below its 80-col floor; the WinResized handler re-asserts
            -- the target width when the outer layout changes.
            vim.wo[term.window].winfixwidth = true
            vim.api.nvim_win_set_width(term.window, ide.term_width())
            -- The side terminal is full-height (nothing above it), so <C-k> nav
            -- is useless here; pass it through to the running app (e.g. Claude Code).
            vim.keymap.set("t", "<C-k>", "<C-k>", { buffer = term.bufnr })
          end
        end,
      })

      -- Tab keymaps for the side terminal (<C-b>{1-9}, etc).
      require("config.terms").setup_keymaps()
      require("config.terms").setup_copymode()
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
      vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
        pattern = "term://*",
        callback = function()
          vim.schedule(function()
            vim.cmd("startinsert")
          end)
        end,
      })

      -- Hold the vertical side terminal at its target width (even split of the
      -- post-explorer region, floored at 80). winfixwidth only blocks automatic
      -- equalization, not the explicit resizes the explorer does on open, so re-assert
      -- the width whenever the layout changes (tree toggled, window resized, etc.).
      local enforcing_term_width = false
      vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
        callback = function()
          if enforcing_term_width then
            return
          end
          enforcing_term_width = true
          local target = ide.term_width()
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            local buf = vim.api.nvim_win_get_buf(win)
            local floating = vim.api.nvim_win_get_config(win).relative ~= ""
            if
              vim.bo[buf].filetype == "toggleterm"
              and not floating
              and vim.api.nvim_win_get_width(win) ~= target
            then
              vim.api.nvim_win_set_width(win, target)
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
      -- <C-g> works from normal and terminal mode (pairs with the <C-t>
      -- side-terminal toggle) so lazygit is reachable wherever the cursor is.
      vim.keymap.set({ "n", "t" }, "<C-g>", function()
        lazygit:toggle()
      end, { desc = "Open lazygit" })
    end,
  },
}
