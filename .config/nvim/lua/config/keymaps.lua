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

-- Shift+Enter inserts a newline in Claude Code's prompt instead of submitting.
-- The program wants ESC CR for that; ghostty's config sends it as text
-- (`keybind = shift+enter=text:\x1b\r`), so under ghostty this never reaches
-- nvim as a chord and the mapping below is inert. Neovide has no equivalent
-- keybind setting -- it hands nvim a real <S-CR>, and nvim's terminal then
-- forwards a bare CR to the child, which submits. So do ghostty's translation
-- here: in terminal mode the rhs is fed to the pty, i.e. \x1b then \r.
--
-- Deliberately NOT the kitty-protocol CSI 13;2u encoding: tmux strips it, and
-- ESC CR survives every layer.
map("t", "<S-CR>", "<Esc><CR>", { desc = "Terminal: send Shift+Enter as ESC CR" })

-- Delete/change never touch the clipboard: without an explicit register they
-- go to the black hole "_. With clipboard=unnamedplus the *default* register
-- reports as '+' (the clipboard), not the unnamed '"', so both must count as
-- "no register given" — otherwise every bare d/x/c looks explicit and cuts to
-- the clipboard, which is the bug this guards against. A genuinely named
-- register is still honoured (`"ad` cuts to a, `"*x` to the primary
-- selection); yank stays the only implicit way text enters the clipboard.
-- Note: because unnamedplus collapses bare `d` and `"+d` onto the same
-- v:register ('+'), `"+d` can't be told from a plain delete and so also
-- blackholes — use `"*` (or yank) to reach the clipboard. Visual p is left
-- native on purpose: pasting over a selection still yanks the replaced text,
-- keeping the swap trick available.
local function blackhole(key)
  return function()
    local reg = vim.v.register
    if reg == '"' or reg == "+" then
      reg = "_"
    end
    return '"' .. reg .. key
  end
end
for _, key in ipairs({ "d", "D", "c", "C", "x", "X" }) do
  map({ "n", "x" }, key, blackhole(key), { expr = true, desc = key .. " without yanking" })
end

-- Ctrl+V pastes the system clipboard, Neovide only. A terminal translates
-- Ctrl+V into a paste event before nvim ever sees it; Neovide hands nvim the
-- raw chord, so without these mappings "paste" silently does visual-block /
-- insert-literal instead. Normal mode is left alone (blockwise visual is worth
-- more than a paste key there), and insert-literal remains on the builtin
-- synonym <C-q>. Terminal mode goes through nvim_paste so the pty gets a
-- proper bracketed paste (Claude Code et al. see one paste, not keystrokes).
if vim.g.neovide then
  map({ "i", "c" }, "<C-v>", "<C-r>+", { desc = "Paste clipboard" })
  map("t", "<C-v>", function()
    vim.api.nvim_paste(vim.fn.getreg("+"), true, -1)
  end, { desc = "Paste clipboard" })
end

-- Clear search highlight
map("n", "<Esc>", "<cmd>nohlsearch<cr>")

-- Save
map({ "n", "i" }, "<C-s>", "<cmd>w<cr>", { desc = "Save file" })

-- Reload current file from disk (checks for on-disk changes). Not under
-- <leader>r: that prefix is the review namespace (triage/nitpick).
map("n", "<leader>R", "<cmd>checktime<cr>", { desc = "Reload file from disk" })

-- Buffer tabs. Switching routes to the main window first (single-main-buffer
-- layout: cycling from the terminal or explorer must not replace that window's
-- buffer).
--
-- BufferLineCycleNext rather than bnext: it walks the buffers bufferline is
-- actually showing, which plugins/buffers.lua filters to the current workspace
-- tabpage's project. Plain bnext walks Vim's global buffer list and would cycle
-- into another project's files -- ones not even on the bar.
local goto_main_window = require("config.windows").goto_main_window
map("n", "<S-l>", function()
  goto_main_window()
  vim.cmd("BufferLineCycleNext")
end, { desc = "Next buffer" })
map("n", "<S-h>", function()
  goto_main_window()
  vim.cmd("BufferLineCyclePrev")
end, { desc = "Prev buffer" })
-- Snacks.bufdelete rather than `bp|bdelete #`: that pair can't close the LAST
-- buffer (with nothing to switch to, bp stays put and there's no alternate to
-- delete), and it lets Vim drop the replacement buffer into whatever window it
-- likes -- hijacking the explorer or terminal. This switches each window showing
-- the buffer off it first, so the layout survives and the main window lands on
-- the greeter (config/greeter.lua) when that was the last one.
map("n", "<leader>x", function()
  require("config.windows").goto_main_window()
  Snacks.bufdelete()
end, { desc = "Close buffer" })
-- All of this workspace's buffers at once, landing back on the greeter
-- (config/greeter.lua) — the fast way back to the tab's "home screen".
map("n", "<leader>X", function()
  require("config.greeter").close_all()
end, { desc = "Close all buffers (this workspace)" })

-- Workspaces: one project per tabpage (see config/workspace.lua). Switching
-- between them is Vim's own gt/gT -- only opening one, listing them, and closing
-- one down are new. <leader>t is "tab"; the test namespace moved to <leader>T
-- (neotest.lua) since these are reached far more often.
map("n", "<leader>tn", function()
  require("config.workspace").pick_new()
end, { desc = "New project tab (recent/dev)" })
-- The same thing for a project the recent list doesn't know (a fresh clone):
-- browse to it instead of naming it.
map("n", "<leader>te", function()
  require("config.workspace").explore()
end, { desc = "New project tab (browse)" })
-- The same thing for a branch of the project you're in: create (or reuse) a
-- worktree for it under .worktrees/ and open that as its own tab. See
-- util/worktree.lua.
map("n", "<leader>tw", function()
  require("util.worktree").pick()
end, { desc = "New project tab (git worktree)" })
map("n", "<leader>tt", function()
  require("config.workspace").pick()
end, { desc = "Switch to open project tab" })
-- :tabclose, but named alongside the others. fishmonger shuts that tabpage's
-- terminals down with it (nothing could reach them afterwards), so this ends the
-- workspace's shells too. Mirrors <leader>x for a buffer.
map("n", "<leader>tx", "<cmd>tabclose<cr>", { desc = "Close project tab" })

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
