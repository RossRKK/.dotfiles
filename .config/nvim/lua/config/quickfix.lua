-- Quickfix entries open in the main window from any window: Vim's own routing lands them over the agent chat.
local M = {}

local windows = require("config.windows")

local step, from_main

--- Open quickfix entries in the main window, from the list and from ]q and friends.
function M.setup()
  local group = vim.api.nvim_create_augroup("quickfix", { clear = true })
  -- switchbuf=uselast skips the greeter (nofile) and opens the entry over the window used last: often the agent chat.
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "qf",
    callback = function(ev)
      if vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].loclist == 1 then
        return
      end
      vim.keymap.set("n", "<CR>", function()
        from_main(vim.fn.line(".") .. "cc")
      end, { buffer = ev.buf, desc = ":cc in the main window" })
    end,
  })
  -- The builtins, but landing in the main window: from the agent chat they would open the file over it.
  for lhs, cmd in pairs({
    ["]q"] = "cnext",
    ["[q"] = "cprevious",
    ["]Q"] = "clast",
    ["[Q"] = "cfirst",
  }) do
    vim.keymap.set("n", lhs, function()
      step(cmd)
    end, { desc = ":" .. cmd .. " in the main window" })
  end
end

--- Run quickfix motion `cmd` with the typed count from the main window.
---@param cmd "cnext"|"cprevious"|"clast"|"cfirst"
function step(cmd)
  -- A count to cfirst/clast is an entry number, so none means the first or last, not entry 1.
  local count = (cmd == "cnext" or cmd == "cprevious") and vim.v.count1
    or (vim.v.count > 0 and vim.v.count or "")
  from_main(count .. cmd)
end

--- Run quickfix command `cmd` from the main window, so the entry opens there.
---@param cmd string
function from_main(cmd)
  windows.goto_main_window()
  local ok, err = pcall(vim.cmd, cmd)
  if not ok then
    vim.notify((tostring(err):gsub("^Vim:", "")), vim.log.levels.ERROR)
  end
end

return M
