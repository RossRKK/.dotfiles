require("config.options")
require("config.keymaps")
require("config.autocmds")
local agent_worktrees = vim.env.AGENT_WORKTREES == "1"
require("util.worktree").setup({
  agent_worktrees = agent_worktrees,
  claude_projects = (vim.env.CLAUDE_CONFIG_DIR or vim.fn.expand("~/.claude")) .. "/projects",
})
require("config.workspace").setup({ agent_worktrees = agent_worktrees })
require("config.lazy")
