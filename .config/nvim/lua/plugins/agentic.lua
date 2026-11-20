-- agentic.nvim: Claude Code as a chat, driven over ACP by claude-agent-acp
-- (claude-agent-acp.nix). That adapter runs home-manager's wrapped claude, so the
-- chat reuses its login and mods; no token. Each chat is a fishmonger tab
-- (config/agent_chat.lua); its own UX and keys as shipped.
return {
  {
    "carlos-algms/agentic.nvim",
    dev = true,
    lazy = true,
    keys = {
      -- i for AI: Space+a is already treesitter's swap-parameter.
      {
        "<leader>i",
        function()
          require("config.agent_chat").toggle()
        end,
        desc = "Agent chat: this workspace's agent tab, or a new one",
      },
    },
    ---@type agentic.PartialUserConfig
    opts = {
      provider = "claude-agent-acp",
    },
  },
}
