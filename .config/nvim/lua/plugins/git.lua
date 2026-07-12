return {
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
        local base = require("review.gitsigns").current
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
