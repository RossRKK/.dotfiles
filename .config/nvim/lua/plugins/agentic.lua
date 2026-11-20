-- agentic.nvim: Claude Code as a chat, driven over ACP by claude-agent-acp
-- (claude-agent-acp.nix). That adapter runs home-manager's wrapped claude, so the
-- chat reuses its login and mods; no token. Each chat is a fishmonger tab
-- (config/agent_chat.lua), made with fishmonger's Ctrl+B a; its own UX and keys as shipped.
return {
  {
    -- Fork carrying the fishmonger-hosting patches until they go upstream.
    "RossRKK/agentic.nvim",
    branch = "rkk/target-window",
    lazy = true,
    ---@type agentic.PartialUserConfig
    opts = {
      provider = "claude-agent-acp",
      -- Agent messages are headed with the name the session's Claude goes by, as its tab is.
      agent_name = function(session_id)
        return require("config.agent_chat").agent_name(session_id)
      end,
      -- No emoji or icon glyphs in the chat's headings, titles and spinner; words and plain marks instead.
      chat_icons = { user = "", agent = "" },
      message_icons = { thinking = ">", finished = "✓", stopped = "■", error = "✗" },
      diagnostic_icons = { error = "E", warn = "W", info = "I", hint = "H" },
      spinner_chars = {
        thinking = { "·", "✢", "✳", "∗", "✻", "✽" },
        searching = { "·", "✢", "✳", "∗", "✻", "✽" },
      },
      -- A sub-agent's work shows as a running summary on its Agent call, not as calls of its own.
      tool_calls = { subagent_activity = "summary" },
      -- The prompt's title is a function, so its buffer name (in the statusline) is set here.
      -- No wrap marker in the chat's prose; agentic sets these :setlocal, so a host window's other tabs keep theirs.
      windows = {
        chat = { win_opts = { showbreak = "NONE" } },
        input = { buffer_name = "Prompt", win_opts = { showbreak = "NONE" } },
        code = { win_opts = { showbreak = "NONE" } },
        files = { win_opts = { showbreak = "NONE" } },
        diagnostics = { win_opts = { showbreak = "NONE" } },
        todos = { win_opts = { showbreak = "NONE" } },
      },
      -- Unbound: in a fishmonger tab agentic's close hid the prompt and left the chat behind.
      keymaps = { widget = { close = {} } },
      headers = {
        chat = { title = "Agentic Chat" },
        input = function(parts, session_state)
          return require("config.agent_chat").input_header(parts, session_state)
        end,
        code = { title = "Selected Code Snippets" },
        files = { title = "Referenced Files" },
        diagnostics = { title = "Diagnostics" },
        todos = { title = "Tasks list" },
      },
    },
  },
}
