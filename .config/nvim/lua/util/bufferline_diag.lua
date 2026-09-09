-- A cheaper diagnostics source for bufferline.
--
-- bufferline's own `diagnostics.get` calls `vim.diagnostic.get()` with no buffer
-- filter on every tabline render. That deep-copies every diagnostic in the
-- session -- and a workspace LSP such as marksman can publish thousands of them
-- for files that were never opened. With several renders a second (see the
-- fishmonger spinner tick) that copy was ~90% of nvim's idle CPU.
--
-- `vim.diagnostic.count()` answers per buffer without copying, and the bar can
-- only show loaded buffers anyway, so ask for exactly those.

local M = {}

-- vim.diagnostic.severity value -> the key bufferline expects in `errors`.
local severity_name = { "error", "warning", "info", "hint" }

--- Turn per-buffer severity counts into bufferline's diagnostics table.
--- Pure, so it can be tested without bufferline loaded.
---@param counts table<integer, table<integer, integer>> bufnr -> (severity -> n), as vim.diagnostic.count returns
---@return table<integer, {count: integer, level: string, errors: table<string, integer>}>
function M.build(counts)
  local result = {}
  for bufnr, by_sev in pairs(counts) do
    local total, worst, errors = 0, nil, {}
    for sev, n in pairs(by_sev) do
      if n > 0 then
        total = total + n
        errors[severity_name[sev] or "other"] = n
        if not worst or sev < worst then
          worst = sev
        end
      end
    end
    if total > 0 then
      result[bufnr] = { count = total, level = severity_name[worst] or "other", errors = errors }
    end
  end
  return result
end

--- Severity counts for every loaded buffer.
---@return table<integer, table<integer, integer>>
function M.collect()
  local counts = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      counts[bufnr] = vim.diagnostic.count(bufnr)
    end
  end
  return counts
end

--- Replace bufferline.diagnostics.get. Keeps bufferline's behaviour of freezing
--- the counts while in insert mode unless `update_in_insert` is set.
function M.install()
  local diag = require("bufferline.diagnostics")
  local last = {}
  local mt = {
    __index = function()
      return { count = 0, level = nil }
    end,
  }
  diag.get = function(opts)
    if opts.diagnostics ~= "nvim_lsp" then
      return setmetatable({}, mt)
    end
    local mode = vim.api.nvim_get_mode().mode
    local insert = mode:sub(1, 1) == "i" or mode:sub(1, 1) == "R"
    if insert and not vim.diagnostic.config().update_in_insert then
      return setmetatable(last, mt)
    end
    last = M.build(M.collect())
    return setmetatable(last, mt)
  end
end

return M
