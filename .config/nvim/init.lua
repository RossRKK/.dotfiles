require("config.options")
require("config.keymaps")
require("config.autocmds")
local agent_worktrees = vim.env.AGENT_WORKTREES == "1"
local claude_dir = vim.env.CLAUDE_CONFIG_DIR or vim.fn.expand("~/.claude")
require("util.worktree").setup({
  agent_worktrees = agent_worktrees,
  claude_projects = claude_dir .. "/projects",
})
require("config.workspace").setup({
  agent_worktrees = agent_worktrees,
  claude_sessions = claude_dir .. "/sessions",
  claude_roles = (vim.env.XDG_CONFIG_HOME or vim.fn.expand("~/.config")) .. "/claude-roles",
})
require("util.workspace_state").setup({
  file = vim.fn.stdpath("state") .. "/workspaces.json",
  claude_projects = claude_dir .. "/projects",
})
require("config.lazy")
