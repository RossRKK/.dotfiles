-- File explorer (neo-tree) + a symbols outline, sharing the left column.
--
-- Two neo-tree sources are used: `filesystem` (the tree) and `document_symbols`
-- (an outline of the focused file, driven by the LSP's documentSymbol request).
-- The branch-review UI paints its triage glyphs on the filesystem tree via a
-- renderer component behind review/adapter; see lua/review/.
--
-- Window routing (which window a file opens into, the side-terminal geometry) is
-- shared with config/ide.lua and config/terms.lua, which key off the "neo-tree"
-- filetype -- keep those in sync if this moves off neo-tree.

return {
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
    lazy = false, -- IDE mode auto-opens it at VimEnter (below)
    config = function()
      -- Copy a tree node's path to the system clipboard (and the unnamed register
      -- so it also pastes with `p`). `modify` is a :h filename-modifiers spec:
      -- ":." for cwd-relative, "" for absolute, ":t" for the bare filename.
      -- neo-tree ships no path-copy command, so these are custom mappings; `y`
      -- itself stays neo-tree's file-copy-to-clipboard.
      local function copy_path(modify)
        return function(state)
          local node = state.tree:get_node()
          if not node or not node.path then
            return
          end
          local path = modify == "" and node.path or vim.fn.fnamemodify(node.path, modify)
          vim.fn.setreg("+", path)
          vim.fn.setreg('"', path)
          vim.notify("Copied: " .. path)
        end
      end

      require("neo-tree").setup({
        sources = { "filesystem", "document_symbols", "git_status" },
        -- Keep focus in the editor when neo-tree closes a window, and don't let
        -- opening a directory hijack the current window (the VimEnter handler
        -- below places the tree as a side panel beside a real editor window).
        open_files_do_not_replace_types = { "terminal", "toggleterm", "trouble", "qf" },
        enable_git_status = true,
        default_component_configs = {
          git_status = {
            symbols = {
              untracked = "?",
              staged = "✓",
              unstaged = "M",
              unmerged = "U",
              renamed = "R",
              deleted = "D",
              ignored = "◌",
              -- Suppress the added/modified word-glyphs neo-tree also shows; the
              -- staged/unstaged marks above already carry the status.
              added = "",
              modified = "",
            },
          },
        },
        window = {
          position = "left",
          width = 35,
          mappings = {
            -- Single left-click opens files and toggles folders, matching the old
            -- nvim-tree behaviour. Double-click also opens (neo-tree default).
            ["<LeftRelease>"] = "open",
            -- Copy the node's path (y stays neo-tree's file copy): gy relative,
            -- gY absolute -- a natural pair.
            ["gy"] = copy_path(":."),
            ["gY"] = copy_path(""),
          },
        },
        filesystem = {
          follow_current_file = { enabled = true },
          -- Don't take over the window when nvim opens on a directory; the
          -- VimEnter handler below arranges the panel explicitly.
          hijack_netrw_behavior = "disabled",
          filtered_items = {
            visible = true, -- show dotfiles and gitignored, just dimmed
            hide_dotfiles = false,
            hide_gitignored = false,
          },
          -- neo-tree resolves components per source, so the branch-review glyph
          -- component is registered on filesystem (not globally) and referenced
          -- from this source's renderers below -- document_symbols keeps its own.
          components = {
            review_status = require("review.adapter").status_component,
          },
          renderers = {
            -- Default filesystem renderers with `review_status` inserted just
            -- before the name, so the triage glyph sits at the front of the row.
            directory = {
              { "indent" },
              { "icon" },
              { "current_filter" },
              {
                "container",
                content = {
                  { "review_status", zindex = 10 },
                  { "name", zindex = 10 },
                  { "clipboard", zindex = 10 },
                  { "diagnostics", errors_only = true, zindex = 20, align = "right", hide_when_expanded = true },
                  { "git_status", zindex = 10, align = "right", hide_when_expanded = true },
                },
              },
            },
            file = {
              { "indent" },
              { "icon" },
              {
                "container",
                content = {
                  { "review_status", zindex = 10 },
                  { "name", zindex = 10 },
                  { "clipboard", zindex = 10 },
                  { "bufnr", zindex = 10 },
                  { "modified", zindex = 20, align = "right" },
                  { "diagnostics", zindex = 20, align = "right" },
                  { "git_status", zindex = 10, align = "right" },
                },
              },
            },
          },
        },
        document_symbols = {
          follow_cursor = true,
        },
      })

      -- The left column stacks two neo-tree windows: the file tree on top, the
      -- symbols outline below it. neo-tree won't stack two sources in one managed
      -- window (a second source at the same position just replaces the first), so
      -- the outline opens in a manual split under the tree via position="current".
      local OUTLINE_HEIGHT = 15

      -- The window in this tab showing neo-tree `source`, or nil.
      local function neotree_win(source)
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
          local buf = vim.api.nvim_win_get_buf(win)
          local ok, src = pcall(vim.api.nvim_buf_get_var, buf, "neo_tree_source")
          if ok and src == source then
            return win
          end
        end
      end

      -- Open the file tree in the left column with the outline stacked beneath it,
      -- leaving focus wherever it started (so it can auto-open without stealing it).
      local function open_sidebar()
        local start_win = vim.api.nvim_get_current_win()
        vim.cmd("Neotree filesystem show left")
        local fs = neotree_win("filesystem")
        if fs and not neotree_win("document_symbols") then
          vim.api.nvim_set_current_win(fs)
          -- `new`, not `split`: a plain empty split, so the window's filetype is
          -- not "neo-tree". position="current" is overridden back to the managed
          -- left window when invoked from inside a neo-tree window (a second left
          -- tree, the "two explorers" bug), so the outline needs a plain host.
          vim.cmd("belowright new")
          vim.cmd("Neotree document_symbols current") -- fill it with the outline
          vim.api.nvim_win_set_height(0, OUTLINE_HEIGHT)
          vim.wo.winfixheight = true -- don't let layout changes reflow the outline
        end
        if vim.api.nvim_win_is_valid(start_win) then
          vim.api.nvim_set_current_win(start_win)
        end
      end

      -- Close every neo-tree window in the tab (both the tree and the outline; the
      -- outline lives in a plain split, so :Neotree close alone wouldn't get it).
      local function close_sidebar()
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
          local buf = vim.api.nvim_win_get_buf(win)
          if pcall(vim.api.nvim_buf_get_var, buf, "neo_tree_source") then
            pcall(vim.api.nvim_win_close, win, false)
          end
        end
      end

      local function toggle_sidebar()
        if neotree_win("filesystem") or neotree_win("document_symbols") then
          close_sidebar()
        else
          open_sidebar()
        end
      end

      vim.keymap.set("n", "<leader>e", toggle_sidebar, { desc = "Toggle explorer + outline" })
      vim.keymap.set("n", "<leader>v", "<cmd>Neotree filesystem reveal left reveal_force_cwd<cr>", {
        desc = "Reveal file in explorer",
      })
      -- Swap the top pane between the file tree and the git_status source (a
      -- changed-files view with per-file stage/unstage/revert/commit keys:
      -- ga/gu/gr/gc/gp/gg). Same managed left window, so the outline split below
      -- stays put; toggles back to the file tree.
      vim.keymap.set("n", "<leader>gt", function()
        if neotree_win("git_status") then
          vim.cmd("Neotree filesystem show left")
        else
          vim.cmd("Neotree git_status show left")
        end
      end, { desc = "Toggle git status in explorer" })

      -- Link neo-tree's git-status highlight groups to semantic groups so the
      -- colours follow any theme.
      local function set_git_highlights()
        vim.api.nvim_set_hl(0, "NeoTreeGitModified", { link = "DiagnosticWarn" })
        vim.api.nvim_set_hl(0, "NeoTreeGitUntracked", { link = "Added" })
        vim.api.nvim_set_hl(0, "NeoTreeGitAdded", { link = "Added" })
        vim.api.nvim_set_hl(0, "NeoTreeGitDeleted", { link = "Removed" })
        vim.api.nvim_set_hl(0, "NeoTreeGitConflict", { link = "DiagnosticError" })
      end
      vim.api.nvim_create_autocmd("ColorScheme", { callback = set_git_highlights })
      set_git_highlights()

      -- `nvim <dir>` (e.g. `nvim .`): open the tree as a side panel beside a real
      -- editor window, so there's always somewhere for files to open.
      vim.api.nvim_create_autocmd("VimEnter", {
        nested = true,
        callback = function(data)
          if vim.fn.argc() ~= 1 or vim.fn.isdirectory(data.file) ~= 1 then
            return
          end
          vim.cmd.cd(vim.fn.fnameescape(data.file))
          vim.cmd.enew() -- empty editor window
          pcall(vim.api.nvim_buf_delete, data.buf, { force = true }) -- drop the dir buffer
          -- Capture the editor window now and restore into it explicitly: if
          -- another window has stolen focus by the time load runs (e.g. Lazy's
          -- update UI popped up on startup), persistence would otherwise :edit
          -- the restored files into the wrong window.
          local editor = vim.api.nvim_get_current_win()
          vim.api.nvim_set_current_win(editor)
          pcall(require("persistence").load) -- reopen this dir's files (no-op if none saved)
          open_sidebar() -- tree + outline stacked in the left column, focus kept here
          vim.api.nvim_set_current_win(editor) -- leave focus in the editor
        end,
      })

      -- Branch review mode: commands, keymaps, gitsigns base, explorer colours.
      require("review").setup()
    end,
  },
}
