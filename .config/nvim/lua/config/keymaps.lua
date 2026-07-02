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

-- Jump to a `path:line:col` reference under the cursor (e.g. printed in the
-- terminal). From a terminal buffer, use Ctrl-\ Ctrl-n first, then gf on the ref.
local function goto_file_ref()
  -- Strip surrounding brackets/quotes/backticks and trailing punctuation.
  local ref = vim.fn.expand("<cWORD>")
  ref = ref:gsub("^[%(%[`'\"]+", ""):gsub("[%)%]`'\",.]+$", "")

  local file, line, col = ref:match("^(.-):(%d+):(%d+)")
  if not file then
    file, line = ref:match("^(.-):(%d+)")
  end
  file = file or ref

  -- Resolve against cwd; fall back to the literal string if that exists.
  local path = vim.fn.fnamemodify(file, ":p")
  if vim.fn.filereadable(path) == 0 and vim.fn.filereadable(file) == 1 then
    path = file
  end
  if vim.fn.filereadable(path) == 0 then
    vim.notify("goto-file: no such file: " .. file, vim.log.levels.WARN)
    return
  end

  -- From the terminal, move to a real editor window before opening.
  if vim.bo.buftype == "terminal" then
    vim.cmd("stopinsert")
    local from = vim.api.nvim_get_current_win()
    vim.cmd("wincmd p")
    if vim.api.nvim_get_current_win() == from then
      vim.cmd("vsplit")
    end
  end

  vim.cmd("edit " .. vim.fn.fnameescape(path))
  if line then
    vim.api.nvim_win_set_cursor(0, { tonumber(line), (tonumber(col) or 1) - 1 })
  end
end

map("n", "gf", goto_file_ref, { desc = "Goto file:line:col under cursor" })
