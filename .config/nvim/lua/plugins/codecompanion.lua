-- CodeCompanion: Claude Code as a chat buffer, driven over ACP by claude-agent-acp
-- (claude-agent-acp.nix). That adapter runs home-manager's wrapped claude, so the
-- chat reuses its login and mods; no token. :AgentChat hosts one in the next free
-- fishmonger tab (util/agent_chat.lua).
return {
  {
    "olimorris/codecompanion.nvim",
    version = "^20",
    dependencies = { "nvim-lua/plenary.nvim", "nvim-treesitter/nvim-treesitter" },
    cmd = { "CodeCompanion", "CodeCompanionChat", "CodeCompanionActions" },
    init = function()
      vim.api.nvim_create_user_command("AgentChat", function()
        require("util.agent_chat").open()
      end, { desc = "Claude Code chat in the next free side-terminal tab" })
    end,
    opts = {
      interactions = { chat = { adapter = "claude_code" } },
      -- fishmonger places the buffer; a chat opened by hand takes the current window.
      display = { chat = { window = { layout = "buffer" } } },
    },
  },
}
