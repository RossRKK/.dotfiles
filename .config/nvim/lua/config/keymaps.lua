local map = vim.keymap.set

-- Window navigation (normal and terminal mode)
map("n", "<C-h>", "<C-w>h", { desc = "Move to left window" })
map("n", "<C-l>", "<C-w>l", { desc = "Move to right window" })
map("n", "<C-j>", "<C-w>j", { desc = "Move to lower window" })
map("n", "<C-k>", "<C-w>k", { desc = "Move to upper window" })
map("t", "<C-h>", "<C-\\><C-n><C-w>h", { desc = "Move to left window" })
map("t", "<C-l>", "<C-\\><C-n><C-w>l", { desc = "Move to right window" })
map("t", "<C-j>", "<C-\\><C-n><C-w>j", { desc = "Move to lower window" })
map("t", "<C-k>", "<C-\\><C-n><C-w>k", { desc = "Move to upper window" })

-- Exit to terminal-normal mode (then gf jumps to a file:line ref under the cursor)
map("t", "<C-n>", "<C-\\><C-n>", { desc = "Terminal: enter normal mode" })

-- Better escape
map("i", "jk", "<Esc>", { desc = "Escape insert mode" })

-- Clear search highlight
map("n", "<Esc>", "<cmd>nohlsearch<cr>")

-- Save
map({ "n", "i" }, "<C-s>", "<cmd>w<cr>", { desc = "Save file" })

-- Reload current file from disk (checks for on-disk changes)
map("n", "<leader>rf", "<cmd>checktime<cr>", { desc = "Reload file from disk" })

-- Buffer tabs
map("n", "<S-l>", "<cmd>bnext<cr>", { desc = "Next buffer" })
map("n", "<S-h>", "<cmd>bprevious<cr>", { desc = "Prev buffer" })
map("n", "<leader>x", "<cmd>bp|bdelete #<cr>", { desc = "Close buffer" })

-- A window is a "main" editor window if it holds an ordinary file buffer — not
-- the terminal, the nvim-tree explorer, or another special/scratch buffer.
local function is_editor_window(win)
  local buf = vim.api.nvim_win_get_buf(win)
  return vim.bo[buf].buftype == "" and vim.bo[buf].filetype ~= "NvimTree"
end

-- Ensure the current window is a main editor window before opening a file, so a
-- file never opens over the terminal or the explorer. Reuses an existing editor
-- window if there is one; otherwise splits off the current window to make one.
local function goto_main_window()
  if is_editor_window(vim.api.nvim_get_current_win()) then
    return
  end
  vim.cmd("stopinsert") -- no-op unless we're in terminal insert mode
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_editor_window(win) then
      vim.api.nvim_set_current_win(win)
      return
    end
  end
  vim.cmd("vsplit")
end

-- Jump to a `path[:line[:col]]` reference under the cursor (e.g. printed in the
-- terminal, or a path in a diff/log). From a terminal buffer, use Ctrl-\ Ctrl-n
-- first, then gf on the ref. Resolution is best-effort and, when it can't pin an
-- exact file, hands the path to the fuzzy finder rather than giving up — so
-- partial paths, paths relative to some other folder, and bare basenames all
-- still land somewhere.
local function goto_file_ref()
  -- Strip surrounding brackets/quotes/backticks and trailing punctuation.
  local ref = vim.fn.expand("<cWORD>")
  ref = ref:gsub("^[%(%[`'\"]+", ""):gsub("[%)%]`'\",.]+$", "")

  -- Pull an optional :line:col (or :line) suffix off the end.
  local rest, line, col = ref:match("^(.-):(%d+):(%d+)$")
  if not rest then
    rest, line = ref:match("^(.-):(%d+)$")
  end
  local token = rest or ref

  -- Candidate spellings: as-is, and a "bare" form with the wrappers that tools
  -- put around paths peeled off, so those resolve too:
  --   * a name(...) wrapper, e.g. Claude Code's Update(<path>) / Read(<path>)
  --   * a git-diff a/ or b/ prefix (diffs render paths as a/<path> and b/<path>)
  --   * a leading ./ and any leftover trailing bracket
  local bare = token
    :gsub("^%w+%(", "")
    :gsub("[%)%]]+$", "")
    :gsub("^[ab]/", "")
    :gsub("^%./", "")
  local spellings = { token }
  if bare ~= token then
    table.insert(spellings, bare)
  end

  -- Roots to resolve a relative path against: cwd, the current file's directory,
  -- and the enclosing git/project root.
  local ok_root, git_root = pcall(vim.fs.root, 0, ".git")
  local roots = { vim.fn.getcwd(), vim.fn.expand("%:p:h"), ok_root and git_root or nil }

  local function resolve(p)
    if p:sub(1, 1) == "/" then
      return vim.fn.filereadable(p) == 1 and p or nil
    end
    for _, root in ipairs(roots) do
      local full = vim.fs.normalize(root .. "/" .. p)
      if vim.fn.filereadable(full) == 1 then
        return full
      end
    end
    return vim.fn.filereadable(p) == 1 and p or nil
  end

  local path
  for _, spelling in ipairs(spellings) do
    path = resolve(spelling)
    if path then
      break
    end
  end

  goto_main_window()
  if path then
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    if line then
      vim.api.nvim_win_set_cursor(0, { tonumber(line), (tonumber(col) or 1) - 1 })
    end
    return
  end

  -- No exact hit: seed the fuzzy finder with the path so a partial or
  -- wrong-folder-relative reference still resolves with a keystroke or two. An
  -- absolute miss can't match the finder's relative results, so seed its
  -- basename instead. (Line/col can't ride through the picker, so drop those.)
  local query = bare:sub(1, 1) == "/" and vim.fn.fnamemodify(bare, ":t") or bare
  require("telescope.builtin").find_files({ default_text = query })
end

map("n", "gf", goto_file_ref, { desc = "Goto file under cursor (fuzzy fallback)" })

-- Yank the current file's path to the clipboard (the reverse of gf), without a
-- trip to the explorer. <leader>yp: path relative to cwd. <leader>yl: with the
-- cursor as path:line:col, so it round-trips straight back through gf.
local function yank_file_path(with_position)
  local path = vim.fn.expand("%:.")
  if path == "" then
    vim.notify("no file in this buffer", vim.log.levels.WARN)
    return
  end
  if with_position then
    local pos = vim.api.nvim_win_get_cursor(0)
    path = ("%s:%d:%d"):format(path, pos[1], pos[2] + 1)
  end
  vim.fn.setreg("+", path)
  vim.notify("yanked: " .. path)
end

map("n", "<leader>yp", function() yank_file_path(false) end, { desc = "Yank file path" })
map("n", "<leader>yl", function() yank_file_path(true) end, { desc = "Yank file path:line:col" })
