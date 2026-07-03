local M = {}

-- Absolute path to the uv .venv interpreter, searching upward from cwd, or nil.
function M.python()
  local venv = vim.fs.find(".venv", {
    upward = true,
    path = vim.fn.getcwd(),
    type = "directory",
    limit = 1,
  })[1]
  if venv then
    local py = venv .. "/bin/python"
    if vim.fn.executable(py) == 1 then
      return py
    end
  end
  return nil
end

return M
