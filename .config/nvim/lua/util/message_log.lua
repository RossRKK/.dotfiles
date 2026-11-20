-- Keeps nvim's message history (Lua callback errors included) in a file that
-- outlives the session. Nvim has no "message shown" event, and ext_messages
-- would take over how snacks shows messages, so the history is polled.
local M = {}

local messages, new_entries

---@class MessageLogOpts
---@field path string the log file; a full one moves aside to `path .. ".1"`
---@field max_bytes integer

---@class MessageLog
---@field private opts MessageLogOpts
---@field private seen string the history text already written
local Log = {}
Log.__index = Log

---@param opts MessageLogOpts
---@return MessageLog
function M.new(opts)
  return setmetatable({ opts = opts, seen = "" }, Log)
end

--- Polls the history every `interval_ms` and once more on exit.
---@param opts MessageLogOpts | { interval_ms: integer }
function M.setup(opts)
  local log = M.new({ path = opts.path, max_bytes = opts.max_bytes })
  local timer = assert(vim.uv.new_timer())
  timer:start(
    opts.interval_ms,
    opts.interval_ms,
    vim.schedule_wrap(function()
      local ok, err = pcall(log.capture, log)
      if not ok then
        -- A failing write would otherwise add an error to the history every tick.
        timer:stop()
        vim.notify("message log stopped: " .. err, vim.log.levels.ERROR)
      end
    end)
  )
  timer:unref()
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      log:capture()
    end,
  })
end

--- Appends the history entries added since the last capture.
function Log:capture()
  local history = messages()
  if history == self.seen then
    return
  end
  local entries = new_entries(history, self.seen)
  self.seen = history
  self:append(entries)
end

---@param entries string[]
function Log:append(entries)
  local stamp = os.date("%Y-%m-%d %H:%M:%S") .. " [" .. vim.fn.getpid() .. "] "
  local text = stamp .. table.concat(entries, "\n" .. stamp) .. "\n"
  vim.fn.mkdir(vim.fs.dirname(self.opts.path), "p")
  local stat = vim.uv.fs_stat(self.opts.path)
  if stat and stat.size + #text > self.opts.max_bytes then
    assert(os.rename(self.opts.path, self.opts.path .. ".1"))
  end
  local file = assert(io.open(self.opts.path, "a"))
  file:write(text)
  file:close()
end

---@param count? integer only the most recent `count` entries
---@return string
function messages(count)
  return vim.api.nvim_exec2((count or "") .. "messages", { output = true }).output
end

--- The newest entries of `history`, oldest first, back to where it overlaps `seen`.
--- `:{k}messages` is the only view of entry boundaries (multi-line text hides them),
--- and the history drops its oldest entries, so `seen` may only match in its tail.
---@param history string
---@param seen string
---@return string[]
function new_entries(history, seen)
  local entries, newer = {}, ""
  for count = 1, math.huge do
    local tail = messages(count)
    table.insert(entries, 1, tail:sub(1, #tail - #newer - (newer == "" and 0 or 1)))
    newer = tail
    local older = history:sub(1, #history - #tail - 1)
    if #tail >= #history or older == seen or vim.endswith(seen, "\n" .. older) then
      return entries
    end
  end
  return entries
end

return M
