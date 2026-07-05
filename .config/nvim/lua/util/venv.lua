local M = {}

-- Absolute path to the uv .venv interpreter, searching upward from the project,
-- or nil. Anchors on the directory argument (`nvim <dir>`) when present: pyright's
-- config resolves this at startup, before explorer.lua cd's into that dir, so
-- getcwd() would still be the launch dir (e.g. ~) and miss the repo's .venv.
function M.python()
  local start = vim.fn.getcwd()
  local arg = vim.fn.argv(0)
  if type(arg) == "string" and arg ~= "" and vim.fn.isdirectory(arg) == 1 then
    start = vim.fn.fnamemodify(arg, ":p")
  end
  local venv = vim.fs.find(".venv", {
    upward = true,
    path = start,
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
