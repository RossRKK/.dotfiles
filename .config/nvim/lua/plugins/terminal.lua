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
        open_mapping = [[<C-t>]],
        hide_numbers = true,
        shade_terminals = false,
        start_in_insert = true,
        shell = "tmux new-session -A -s neovim",
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
            -- In normal mode <C-b> would otherwise be a no-op nvim key. Send the
            -- tmux prefix (0x02) straight to the job and resume terminal mode, so
            -- tmux shortcuts work without first pressing i to re-enter the terminal.
            vim.keymap.set("n", "<C-b>", function()
              vim.api.nvim_chan_send(vim.b.terminal_job_id, "\2")
              vim.cmd("startinsert")
            end, { buffer = term.bufnr, desc = "Send tmux prefix and resume terminal" })
          end
        end,
      })

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
            require("toggleterm").toggle(1, ide.term_width(), nil, "vertical")
            vim.cmd("wincmd p")
            vim.cmd("stopinsert")
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

      -- Keep the terminal in terminal-mode through a mouse drag-selection (e.g.
      -- tmux copy-mode) that strays over the split boundary. Per :help terminal, a
      -- mouse event over another window drops the terminal from terminal-mode into
      -- terminal-normal in place (no window switch) and nvim starts its own visual
      -- selection there, killing the in-flight tmux selection. Two parts:
      --   1. In the terminal buffer's normal/visual mode, <LeftDrag>/<LeftRelease>
      --      are no-ops, so a stray drag can't begin a visual selection. Terminal-
      --      mode drags are untouched and still forward to tmux.
      --   2. When a mouse (not a keyboard <C-\><C-n>) knocks us out of terminal-
      --      mode, resume it immediately. The <LeftDrag> timestamp tells the two
      --      apart, so keyboard normal-mode for gf/scrollback is preserved.
      local drag_group = vim.api.nvim_create_augroup("terminal_drag_guard", { clear = true })
      local last_drag_ms = 0
      vim.on_key(function(key)
        if #key >= 3 and vim.fn.keytrans(key) == "<LeftDrag>" then
          last_drag_ms = vim.uv.now()
        end
      end, vim.api.nvim_create_namespace("terminal_drag_guard"))

      local function nop_terminal_drag(buf)
        for _, lhs in ipairs({ "<LeftDrag>", "<LeftRelease>" }) do
          pcall(vim.keymap.set, { "n", "x" }, lhs, "<Nop>", { buffer = buf })
        end
      end
      vim.api.nvim_create_autocmd("FileType", {
        group = drag_group,
        pattern = "toggleterm",
        callback = function(args)
          nop_terminal_drag(args.buf)
        end,
      })

      vim.api.nvim_create_autocmd("TermLeave", {
        group = drag_group,
        callback = function()
          local buf = vim.api.nvim_get_current_buf()
          if vim.bo[buf].filetype ~= "toggleterm" then
            return
          end
          -- A keyboard <C-\><C-n> has no recent drag: leave us in normal mode.
          if vim.uv.now() - last_drag_ms > 300 then
            return
          end
          vim.schedule(function()
            local b = vim.api.nvim_get_current_buf()
            if vim.bo[b].filetype ~= "toggleterm" then
              return
            end
            local mode = vim.api.nvim_get_mode().mode
            if mode ~= "t" then
              if mode:match("[vV\022]") then
                vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
              end
              vim.cmd("startinsert")
            end
          end)
        end,
      })

      -- Hold the vertical side terminal at its target width (even split of the
      -- post-explorer region, floored at 80). winfixwidth only blocks automatic
      -- equalization, not the explicit resizes nvim-tree does on open, so re-assert
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
            if vim.bo[buf].filetype == "toggleterm" and not floating and vim.api.nvim_win_get_width(win) ~= target then
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
