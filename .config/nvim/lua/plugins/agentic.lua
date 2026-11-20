-- agentic.nvim: Claude Code as a chat, driven over ACP by claude-agent-acp
-- (claude-agent-acp.nix). That adapter runs home-manager's wrapped claude, so the
-- chat reuses its login and mods; no token. Each chat is a fishmonger tab
-- (config/agent_chat.lua), made with fishmonger's Ctrl+B A; its own UX and keys as shipped.
return {
  {
    "carlos-algms/agentic.nvim",
    dev = true,
    lazy = true,
    ---@type agentic.PartialUserConfig
    opts = {
      provider = "claude-agent-acp",
      headers = {
        input = function(parts, session_state)
          return require("config.agent_chat").input_header(parts, session_state)
        end,
      },
    },
  },
}
