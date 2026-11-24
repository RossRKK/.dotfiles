-- GitHub PRs as editable buffers: the greeter shows the branch's PR in one
-- (config/greeter.lua), where :w saves edits to its title, body and comments.
return {
  {
    "pwntester/octo.nvim",
    dependencies = { "nvim-lua/plenary.nvim", "folke/snacks.nvim", "nvim-tree/nvim-web-devicons" },
    cmd = "Octo",
    opts = {
      picker = "snacks",
      -- Personal repos' remotes go through an SSH alias for a second GitHub key.
      ssh_aliases = { ["github-personal"] = "github.com" },
      -- Reloads a PR buffer when GitHub's copy changes, unless it holds unsaved edits.
      -- A minute apart: each buffer kept open (one per branch shown) is a query per poll.
      poll = { enabled = true, interval = 60 * 1000, notify_on_refresh = false },
      -- Off Ctrl keys: <C-b> is fishmonger's terminal prefix, <C-r> redo and <C-y>/<C-e> scrolling.
      mappings = {
        pull_request = {
          reload = { lhs = "<localleader>pu", desc = "reload PR" },
          open_in_browser = { lhs = "<localleader>pw", desc = "open PR in browser" },
          copy_url = { lhs = "<localleader>py", desc = "copy url to system clipboard" },
          copy_sha = { lhs = "<localleader>pY", desc = "copy commit SHA to system clipboard" },
        },
      },
    },
    config = function(_, opts)
      require("octo").setup(opts)
      -- Octo's buffers hold markdown, so treesitter and render-markdown parse them as such.
      vim.treesitter.language.register("markdown", "octo")
    end,
  },
}
