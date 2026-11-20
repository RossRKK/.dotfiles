-- Claude Code chats (CodeCompanion over ACP, plugins/codecompanion.lua) made as
-- buffers in no window, for fishmonger to host as a tab.

local M = {}

--- A new chat in the current workspace's next free fishmonger tab.
function M.open()
  local buf = M.new()
  if not require("fishmonger").new({ buf = buf }) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end

--- A new chat with no window yet: its buffer. Its agent starts a tick later, in
--- the cwd current then, with `env` added to its environment.
---@param env? table<string, string>
---@return integer
function M.new(env)
  local adapter = require("codecompanion.adapters").extend("claude_code", { env = env or {} })
  local chat = require("codecompanion").chat({ params = { adapter = adapter }, hidden = true })
  -- CodeCompanion scrolls, folds and checks visibility in the window it last showed the chat in.
  vim.api.nvim_create_autocmd("BufWinEnter", {
    buffer = chat.bufnr,
    callback = function()
      chat.ui:show_in_win({ winnr = vim.api.nvim_get_current_win() })
    end,
  })
  return chat.bufnr
end

return M
