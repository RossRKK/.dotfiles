require("config.options")
require("config.keymaps")
require("config.autocmds")
require("util.worktree").setup({
  agent_worktrees = vim.env.AGENT_WORKTREES == "1",
  claude_projects = (vim.env.CLAUDE_CONFIG_DIR or vim.fn.expand("~/.claude")) .. "/projects",
})
require("config.lazy")
