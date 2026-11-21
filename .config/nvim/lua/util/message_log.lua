-- Keeps every message (Lua errors and their tracebacks too) in a file that
-- outlives the session: 'verbosefile' gets all message output, while
-- :messages and the screen still get theirs.
local M = {}

--- Points 'verbosefile' at a new log for this nvim, after deleting all but the
--- newest `keep_previous` logs other nvims left in `dir`.
---@param opts { dir: string, keep_previous: integer }
function M.setup(opts)
  vim.fn.mkdir(opts.dir, "p")
  local logs = vim.fn.glob(opts.dir .. "/messages-*.log", true, true)
  -- Names start with the start time, so name order is age order.
  table.sort(logs)
  for i = 1, #logs - opts.keep_previous do
    os.remove(logs[i])
  end
  -- The file has no timestamps of its own, so the name carries when and which nvim.
  local name = ("messages-%s-%d.log"):format(os.date("%Y%m%d-%H%M%S"), vim.fn.getpid())
  vim.o.verbosefile = opts.dir .. "/" .. name
end

return M
