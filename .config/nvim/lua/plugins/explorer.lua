-- File explorer (neo-tree) in the left column, plus an on-demand symbols popup.
--
-- Two neo-tree sources are used: `filesystem` (the docked tree) and
-- `document_symbols` (a float outlining the focused file, driven by the LSP's
-- documentSymbol request; <leader>lo).
-- The branch-review UI paints its triage/nitpick glyphs on the filesystem tree
-- via renderer components (registered below); those come from the triage.nvim /
-- nitpick.nvim plugins, wired in lua/plugins/review.lua.
--
-- Window routing (which window a file opens into, the side-terminal geometry) is
-- shared with config/ide.lua and fishmonger, which key off the "neo-tree"
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

      -- Open a node's directory (a file's parent, a directory itself) as its own
      -- workspace tabpage: promote a subdirectory of the current project, or jump
      -- straight into a sibling repo you happened to be looking at.
      local function open_workspace(state)
        local node = state.tree:get_node()
        if not node or not node.path then
          return
        end
        local dir = node.type == "directory" and node.path or vim.fn.fnamemodify(node.path, ":h")
        require("config.workspace").open(dir, { tab = true })
      end

      require("neo-tree").setup({
        sources = { "filesystem", "document_symbols", "git_status" },
        -- Keep focus in the editor when neo-tree closes a window, and don't let
        -- opening a directory hijack the current window (the VimEnter handler
        -- below places the tree as a side panel beside a real editor window).
        open_files_do_not_replace_types = { "terminal", "fishmonger", "trouble", "qf" },
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
            -- g-prefixed like the pair above, and out of neo-tree's way: plain
            -- `w` is its open_with_window_picker.
            ["gw"] = open_workspace,
            -- `e` toggles neo-tree's auto-expand-width (fit the longest name).
            -- edgy owns the panel width, but the expand fires WinResized and
            -- util/edgy_pin.lua writes the new width into edgy's override, so
            -- it sticks instead of snapping back -- no more flicker.
            ["e"] = "toggle_auto_expand_width",
            -- neo-tree's default <C-r> = clear_clipboard is a filesystem-only
            -- command, but window.mappings apply to every source, so the
            -- document_symbols / git_status sources error on it each startup.
            -- Unbind it (unused).
            ["<C-r>"] = "none",
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
          -- neo-tree resolves components per source, so the triage glyph and the
          -- nitpick comment marker are registered on filesystem (not globally) and
          -- referenced from this source's renderers below -- document_symbols keeps
          -- its own.
          components = {
            triage_status = require("triage.adapter").status_component,
            nitpick_marker = require("nitpick.adapter").marker_component,
          },
          renderers = {
            -- Default filesystem renderers with `triage_status` and the
            -- `nitpick_marker` inserted just before the name, so the triage glyph
            -- and comment bubble sit at the front of the row.
            directory = {
              { "indent" },
              { "icon" },
              { "current_filter" },
              {
                "container",
                content = {
                  { "triage_status", zindex = 10 },
                  { "nitpick_marker", zindex = 10 },
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
                  { "triage_status", zindex = 10 },
                  { "nitpick_marker", zindex = 10 },
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
          -- The outline is a popup, not a docked panel: it used to sit under the
          -- tree in the left column, where <C-h> landed on it as often as on the
          -- explorer and closing the main buffer left the column stranded.
          window = { position = "float" },
        },
      })

      -- The left column holds one neo-tree window: the file tree. It opens with
      -- `show` (which doesn't steal focus) and edgy relocates it into the
      -- left-edge slot (see lua/plugins/edgy.lua). Opening and closing that
      -- column lives in util.sidebar -- config.workspace opens one per project
      -- tabpage, so it can't stay local to this file.
      local sidebar = require("util.sidebar")

      vim.keymap.set("n", "<leader>e", sidebar.toggle, { desc = "Toggle explorer" })
      -- The symbols outline, on demand as a float. `toggle` so the same key
      -- dismisses it; `reveal` follows the cursor's symbol on open.
      vim.keymap.set("n", "<leader>lo", "<cmd>Neotree document_symbols float toggle reveal<cr>", {
        desc = "Outline (symbols popup)",
      })
      vim.keymap.set("n", "<leader>v", "<cmd>Neotree filesystem reveal left reveal_force_cwd<cr>", {
        desc = "Reveal file in explorer",
      })
      -- Swap the top pane between the file tree and the git_status source (a
      -- changed-files view with per-file stage/unstage/revert/commit keys:
      -- ga/gu/gr/gc/gp/gg). Same managed left window, so the outline split below
      -- stays put; toggles back to the file tree.
      vim.keymap.set("n", "<leader>gt", function()
        if sidebar.win("git_status") then
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

      -- `nvim <dir>` (e.g. `nvim .`): build the first workspace -- the tree
      -- beside a real editor window, side terminal on the right. Same open() the
      -- <leader>tn picker calls for a second project, minus the new tabpage: this
      -- one takes the tabpage nvim started in, and the global cwd with it.
      vim.api.nvim_create_autocmd("VimEnter", {
        nested = true,
        callback = function(data)
          -- config.ide is the single owner of the "opened on a directory" detection.
          local dir = require("config.ide").dir()
          if not dir then
            return
          end
          require("config.workspace").open(dir, { drop_buf = data.buf })
        end,
      })

      -- Branch review mode (triage.nvim + nitpick.nvim) is declared and wired in
      -- plugins/review.lua. Their neo-tree glyphs are registered above as the
      -- triage_status / nitpick_marker components.
    end,
  },
}
