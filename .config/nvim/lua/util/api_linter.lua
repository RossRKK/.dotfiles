-- Google's AIP linter (github.com/googleapis/api-linter) run on any proto the
-- way a buf repo's hook runs it: from the proto root, on the file named
-- relative to it, with our own config rather than the repo's (whose opt-outs
-- exist to pass CI, not to hide problems while editing).
local M = {}

---@class api_linter.Paths
---@field config string the api-linter config every proto is linted with
---@field common_protos string googleapis' common protos (google/api/...), for repos that don't vendor them

---@type api_linter.Paths
M.paths = {
  config = vim.fn.stdpath("config") .. "/api-linter.yaml",
  -- Linked by home-manager (base.nix).
  common_protos = vim.fn.stdpath("data") .. "/googleapis-protos",
}

---@param file string absolute path of a .proto file
---@return string root where its imports resolve from: the buf module, else the git checkout, else its own directory
function M.proto_root(file)
  return vim.fs.root(file, { "buf.yaml", ".git" }) or vim.fs.dirname(file)
end

---@param file string absolute path of the .proto file to lint
---@param paths api_linter.Paths
---@return lint.Linter
function M.linter(file, paths)
  local root = M.proto_root(file)
  return {
    cmd = "api-linter",
    cwd = root,
    stdin = false,
    append_fname = false,
    args = {
      -- The repo's own path first, so its vendored copies of the common protos win.
      "--proto-path",
      ".",
      "--proto-path",
      paths.common_protos,
      "--config",
      paths.config,
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
