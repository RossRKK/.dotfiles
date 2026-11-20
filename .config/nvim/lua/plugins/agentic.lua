-- agentic.nvim: Claude Code as a chat sidebar, driven over ACP by claude-agent-acp
-- (claude-agent-acp.nix). That adapter runs home-manager's wrapped claude, so the
-- chat reuses its login and mods; no token. Its own UX, keys and layout as shipped.
return {
  {
    "carlos-algms/agentic.nvim",
    lazy = true,
    ---@type agentic.PartialUserConfig
    opts = {
      provider = "claude-agent-acp",
    },
  },
}
