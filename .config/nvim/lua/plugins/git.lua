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
        map("<leader>hd", gs.diffthis, "Diff current file vs HEAD")
        map("<leader>hp", gs.preview_hunk, "Preview hunk")
        map("<leader>hs", gs.stage_hunk, "Stage hunk")
        map("<leader>hr", gs.reset_hunk, "Reset hunk")
        map("<leader>hb", function()
          gs.blame_line({ full = true })
        end, "Blame line (popup)")
        map("<leader>hB", gs.toggle_current_line_blame, "Toggle inline blame")
      end,
    },
  },
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory", "DiffviewToggleFiles" },
    keys = {
      { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Diffview: uncommitted changes" },
      { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview: current file history" },
      {
        "<leader>gb",
        function()
          -- Whole-branch diff: everything since the merge-base with the default branch.
          local default = vim.fn.systemlist({
            "git",
            "symbolic-ref",
            "--quiet",
            "--short",
            "refs/remotes/origin/HEAD",
          })[1]
          if not default or default == "" then
            default = "origin/main"
          end
          vim.cmd("DiffviewOpen " .. default .. "...HEAD")
        end,
        desc = "Diffview: whole-branch diff",
      },
    },
    opts = {
      keymaps = {
        view = { { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Close Diffview" } } },
        file_panel = { { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Close Diffview" } } },
        file_history_panel = { { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Close Diffview" } } },
      },
    },
  },
}
