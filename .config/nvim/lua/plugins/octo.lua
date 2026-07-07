-- GitHub PRs/issues inside nvim: browse, comment, and submit reviews.
-- Talks to GitHub via the `gh` CLI (already authed) + GraphQL. Complements the
-- local branch-triage tool in lua/review/ rather than replacing it: octo is the
-- GitHub-side conversation (comments others see, review verdict), review/ is the
-- personal merge-result triage ledger.
return {
  {
    "pwntester/octo.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    cmd = "Octo",
    keys = {
      { "<leader>op", "<cmd>Octo pr list<cr>", desc = "Octo: list PRs" },
      { "<leader>oP", "<cmd>Octo pr search<cr>", desc = "Octo: search PRs" },
      { "<leader>oo", "<cmd>Octo pr checkout<cr>", desc = "Octo: checkout PR under cursor" },
      { "<leader>oi", "<cmd>Octo issue list<cr>", desc = "Octo: list issues" },
      { "<leader>or", "<cmd>Octo review start<cr>", desc = "Octo: start review" },
      { "<leader>oR", "<cmd>Octo review resume<cr>", desc = "Octo: resume pending review" },
      { "<leader>oc", "<cmd>Octo pr commits<cr>", desc = "Octo: PR commits" },
      { "<leader>oa", "<cmd>Octo actions<cr>", desc = "Octo: pick any action" },
    },
    opts = {
      picker = "telescope",
      -- Fetch review-diff file contents from the working tree when the checked-out
      -- commit matches, so large diffs render without extra API round-trips.
      use_local_fs = true,
    },
  },
}
