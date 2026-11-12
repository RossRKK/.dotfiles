-- Google's AIP linter (github.com/googleapis/api-linter) run the way a repo's
-- own hook runs it: from the directory holding its config, as the proto path,
-- on the file named relative to it (the config's included_paths match that).
local M = {}

-- api-linter reads no config unless one is passed, so these are the names looked for.
local config_names = { "api-linter.yaml", ".api-linter.yaml" }

---@param file string absolute path of a .proto file
---@return string|nil config the nearest api-linter config above `file`
function M.find_config(file)
  return vim.fs.find(config_names, { path = vim.fs.dirname(file), upward = true, type = "file" })[1]
end

---@param config string absolute path of the repo's api-linter config
---@param file string absolute path of the .proto file to lint
---@return lint.Linter
function M.linter(config, file)
  local root = vim.fs.dirname(config)
  return {
    cmd = "api-linter",
    cwd = root,
    stdin = false,
    append_fname = false,
    args = {
      "--proto-path",
      ".",
      "--config",
      vim.fs.basename(config),
      "--output-format",
      "json",
      assert(vim.fs.relpath(root, file)),
    },
    stream = "stdout",
    parser = M.parse,
  }
end

---@param output string api-linter's `--output-format json` stdout, empty when it failed
---@return vim.Diagnostic[]
function M.parse(output)
  if output == "" then
    return {}
  end
  local diagnostics = {}
  for _, file in ipairs(vim.json.decode(output)) do
    for _, problem in ipairs(file.problems) do
      local start, stop = problem.location.start_position, problem.location.end_position
      table.insert(diagnostics, {
        -- api-linter is 1-based and its end column inclusive; vim.Diagnostic is 0-based, end exclusive.
        lnum = start.line_number - 1,
        col = start.column_number - 1,
        end_lnum = stop.line_number - 1,
        end_col = stop.column_number,
        severity = vim.diagnostic.severity.WARN,
        source = "api-linter",
        code = problem.rule_id,
        message = problem.message,
      })
    end
  end
  return diagnostics
end

return M
