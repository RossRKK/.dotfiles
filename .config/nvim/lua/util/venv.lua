local M = {}

-- Absolute path to the uv .venv interpreter, searching upward from the project,
-- or nil. Anchors on the directory argument (`nvim <dir>`) when present: pyright's
-- config resolves this at startup, before explorer.lua cd's into that dir, so
-- getcwd() would still be the launch dir (e.g. ~) and miss the repo's .venv.
function M.python()
  -- config.ide resolves the directory argument once at startup (see its notes
  -- on why argv must be read before the VimEnter cd).
  local start = require("config.ide").dir() or vim.fn.getcwd()
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
