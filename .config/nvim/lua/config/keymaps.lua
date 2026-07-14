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

-- A window is a "main" editor window only if it positively holds an ordinary,
-- listed file buffer. This is an allowlist on purpose: anything else — the
-- terminal, the neo-tree explorer, and every floating/scratch menu (Lazy's
-- update UI, help peeks, quickfix) — is not a target, without having to name it.
local function is_editor_window(win)
  -- Floating windows (Lazy, notifications, help peeks) are never editor targets.
  if vim.api.nvim_win_get_config(win).relative ~= "" then
    return false
  end
  local buf = vim.api.nvim_win_get_buf(win)
  return vim.bo[buf].buftype == "" and vim.bo[buf].buflisted
end

-- Ensure the current window is a main editor window before opening a file, so a
-- file never opens over the terminal or the explorer. Reuses an existing editor
-- window if there is one. Never splits: splitting the terminal (or a diagnostic
-- float) to make a window just leaves a stray, wrong-width split. If no editor
-- window exists at all, we fall through and open in the current window.
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
end

-- Parse a `path[:line[:col]]` reference (e.g. printed in the terminal, or a path
-- in a diff/log) and resolve it to a real file on disk. Best-effort: returns
-- `path, line, col, bare` where `path` is the resolved absolute file (nil if
-- nothing matched) and `bare` is the cleaned token for a fuzzy fallback. This is
-- the pattern-matching half shared by gy (yank), gp/gf (open) — gf = gy then gp.
local function resolve_ref(ref)
  -- Strip surrounding brackets/quotes/backticks and trailing punctuation.
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
  local bare = token:gsub("^%w+%(", ""):gsub("[%)%]]+$", ""):gsub("^[ab]/", ""):gsub("^%./", "")
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

  return path, line, col, bare
end

-- Jump to a reference (a path[:line[:col]] string, e.g. from a register), in the
-- main editor window. Resolves with resolve_ref; a miss just reports it rather
-- than falling back to a fuzzy find — that's Ctrl-P's job.
local function goto_ref(ref)
  local path, line, col = resolve_ref(ref)
  if not path then
    vim.notify("no file resolved from: " .. ref, vim.log.levels.WARN)
    return
  end
  goto_main_window()
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  if line then
    vim.api.nvim_win_set_cursor(0, { tonumber(line), (tonumber(col) or 1) - 1 })
  end
end

-- gf/gF: native "goto file under cursor", differing from the builtins in exactly
-- one way — the file opens in the main editor window, not the current one — so it
-- works from the terminal (the primary use case: jump to a path a program
-- printed; enter terminal-normal mode first with Ctrl-\ Ctrl-n / <C-n>). Resolution
-- is Vim's own: <cfile> for the name, findfile() honouring 'path'/'suffixesadd'.
-- No wrapper-stripping or fuzzy fallback — for a wrapped path use yi( then
-- <leader>o, for a guess use Ctrl-P. gF additionally jumps to a trailing line
-- number (foo.rs:42), like the builtin. Routing happens before the edit, so the
-- terminal is never replaced.
local function goto_file_main(with_line)
  local cfile = vim.fn.expand("<cfile>")
  if cfile == "" then
    vim.notify("gf: no file name under cursor", vim.log.levels.WARN)
    return
  end
  local found = vim.fn.findfile(cfile)
  if found == "" then
    vim.notify("gf: can't find " .. cfile .. " in 'path'", vim.log.levels.WARN)
    return
  end
  -- gF: the number trailing the name on this line (foo.rs:42, foo.rs 42, :42:5).
  local line
  if with_line then
    local after = vim.api.nvim_get_current_line():match(vim.pesc(cfile) .. "%D*(%d+)")
    line = after and tonumber(after)
  end
  goto_main_window()
  vim.cmd("edit " .. vim.fn.fnameescape(found))
  if line then
    pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
  end
end
map("n", "gf", function()
  goto_file_main(false)
end, { desc = "Goto file under cursor (main window)" })
map("n", "gF", function()
  goto_file_main(true)
end, { desc = "Goto file:line under cursor (main window)" })

-- <leader>o: open (goto) the path held in a register, in the main window.
-- Register-aware the Vim way — `"a<leader>o` reads register a; a bare <leader>o
-- reads the unnamed register, which here is the system clipboard (clipboard=
-- unnamedplus). Trim surrounding whitespace so a copied path with a stray
-- trailing newline still resolves.
map("n", "<leader>o", function()
  local reg = vim.v.register -- register you prefixed, else the unnamed " (= clipboard)
  local ref = (vim.fn.getreg(reg) or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if ref == "" then
    vim.notify("register " .. reg .. " is empty", vim.log.levels.WARN)
    return
  end
  goto_ref(ref)
end, { desc = "Open path from register (default: clipboard)" })

-- Yank the current (open) file's path, without a trip to the explorer.
-- <leader>yf ("yank file"): path relative to cwd. <leader>yl: with the cursor
-- line as path:line, so it round-trips straight back through gf / <leader>o.
-- Register-aware like the other path commands: `"a<leader>yf` yanks into register
-- a; bare uses the unnamed register, which defaults to + (clipboard) here.
local function yank_file_path(with_line)
  local path = vim.fn.expand("%:.")
  if path == "" then
    vim.notify("no file in this buffer", vim.log.levels.WARN)
    return
  end
  if with_line then
    path = ("%s:%d"):format(path, vim.api.nvim_win_get_cursor(0)[1])
  end
  vim.fn.setreg(vim.v.register, path)
  vim.notify("yanked: " .. path)
end

map("n", "<leader>yf", function()
  yank_file_path(false)
end, { desc = "Yank open file path" })
map("n", "<leader>yl", function()
  yank_file_path(true)
end, { desc = "Yank open file path:line" })
