return {
  {
    -- A second snacks fragment (config lives in terminal.lua); lazy merges `keys`
    -- across fragments, so this PR map sits with the other <leader>g git maps.
    -- Resolve the current branch's PR via snacks, then :edit its gh:// uri: the
    -- first read of a gh:// buffer trips snacks' bootstrap BufReadCmd, which
    -- renders the PR in the current window. In-buffer keymaps drive the actions
    -- (<cr> action menu, c/i/a/o). (Snacks.gh.open, the documented one-shot, isn't
    -- implemented in this version; the picker's "Open in buffer" jump is flaky.)
    "folke/snacks.nvim",
    keys = {
      {
        "<leader>gP",
        function()
          -- current_pr() spawns gh via snacks' async runtime, so it must run in an
          -- async coroutine; the buffer edit then goes back on the main loop.
          require("snacks.picker.util.async").new(function()
            local pr = require("snacks.gh.api").current_pr()
            vim.schedule(function()
              if not pr then
                vim.notify("gh: no open PR for the current branch", vim.log.levels.WARN)
                return
              end
              vim.cmd.edit(pr.uri)
            end)
          end)
        end,
        desc = "Open current branch's PR in buffer (gh)",
      },
    },
  },
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      -- Inline blame of the current line as dimmed virtual text at end of line.
      current_line_blame = true,
      current_line_blame_opts = { virt_text_pos = "eol", delay = 0 },
      current_line_blame_formatter = "  <author>, <author_time:%R> · <summary>",
      on_attach = function(bufnr)
        local gs = require("gitsigns")
        -- Review mode rebases the sign column onto the branch merge-base; make
        -- sure buffers that attach after that base was chosen inherit it.
        local base = require("triage.gitsigns").current
        if base then
          pcall(gs.change_base, base, true)
        end
        local function map(l, r, desc)
          vim.keymap.set("n", l, r, { buffer = bufnr, desc = desc })
        end
        map("]h", function()
          gs.nav_hunk("next")
        end, "Next hunk")
        map("[h", function()
          gs.nav_hunk("prev")
        end, "Prev hunk")
        -- Inline diff vs HEAD (deleted lines as virtual text, changed lines
        -- highlighted word-level in the buffer) instead of a side-by-side split,
        -- so the fixed window layout stays put. Toggle, since the overlay is
        -- persistent. Same gitsigns machinery as triage's <leader>rd, but against
        -- HEAD (gitsigns' default base) rather than the review base.
        map("<leader>gd", function()
          gs.toggle_deleted()
          gs.toggle_linehl()
          gs.toggle_word_diff()
        end, "Toggle inline diff vs HEAD")
        map("<leader>gp", gs.preview_hunk, "Preview hunk")
        map("<leader>gs", gs.stage_hunk, "Stage hunk")
        map("<leader>gr", gs.reset_hunk, "Reset hunk")
        map("<leader>gb", function()
          gs.blame_line({ full = true })
        end, "Blame line (popup)")
        map("<leader>gB", gs.toggle_current_line_blame, "Toggle inline blame")
      end,
    },
  },
  {
    -- In-buffer conflict resolution that respects a fixed window layout: it
    -- highlights ours/theirs regions and picks a side in place (co/ct/cb/c0,
    -- ]x/[x) instead of spawning 3-way diff splits.
    "akinsho/git-conflict.nvim",
    version = "*",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      -- Off: the c-prefixed defaults (co/ct/cb/c0) shadow Vim's change operator
      -- (ct{char}, cb). We bind our own under <leader>g below instead.
      default_mappings = false,
      -- Leave the plugin's own suppression off: on nvim >=0.11 it calls the
      -- removed vim.diagnostic.disable() and errors. We do it below with the
      -- current API instead.
      disable_diagnostics = false,
    },
    config = function(_, opts)
      require("git-conflict").setup(opts)

      -- Keep the side the cursor is in: above the `=======` is ours, below theirs.
      -- No-op unless the cursor is actually between a <<< and its >>> (a nearer
      -- start marker above than an end marker means we're inside a conflict).
      local function choose_here()
        if vim.fn.search("^<<<<<<<", "bnW") <= vim.fn.search("^>>>>>>>", "bnW") then
          return
        end
        local sep = vim.fn.search("^=======", "bnW")
        vim.cmd(vim.api.nvim_win_get_cursor(0)[1] > sep and "GitConflictChooseTheirs" or "GitConflictChooseOurs")
      end

      local grp = vim.api.nvim_create_augroup("GitConflictDiagnostics", { clear = true })
      -- Only while a buffer is conflicted: quiet LSP errors on the marker lines
      -- and attach the leader maps (so they don't linger on clean buffers).
      vim.api.nvim_create_autocmd("User", {
        group = grp,
        pattern = "GitConflictDetected",
        callback = function(ev)
          vim.diagnostic.enable(false, { bufnr = ev.buf })
          local function map(lhs, cmd, desc)
            vim.keymap.set("n", lhs, "<cmd>" .. cmd .. "<cr>", { buffer = ev.buf, desc = desc })
          end
          vim.keymap.set("n", "<leader>cc", choose_here, { buffer = ev.buf, desc = "Conflict: keep this one (under cursor)" })
          map("<leader>co", "GitConflictChooseOurs", "Conflict: keep ours (HEAD)")
          map("<leader>ct", "GitConflictChooseTheirs", "Conflict: keep theirs")
          map("<leader>cb", "GitConflictChooseBoth", "Conflict: keep both")
          map("<leader>c0", "GitConflictChooseNone", "Conflict: keep neither")
          map("]x", "GitConflictNextConflict", "Next conflict")
          map("[x", "GitConflictPrevConflict", "Prev conflict")
        end,
      })
      vim.api.nvim_create_autocmd("User", {
        group = grp,
        pattern = "GitConflictResolved",
        callback = function(ev)
          vim.diagnostic.enable(true, { bufnr = ev.buf })
          for _, lhs in ipairs({ "<leader>cc", "<leader>co", "<leader>ct", "<leader>cb", "<leader>c0", "]x", "[x" }) do
            pcall(vim.keymap.del, "n", lhs, { buffer = ev.buf })
          end
        end,
      })
    end,
  },
}
