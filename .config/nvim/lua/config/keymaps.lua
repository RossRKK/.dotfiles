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

-- Shift+Enter is deliberately NOT mapped in terminal mode. Claude Code turns on
-- the kitty keyboard protocol, and nvim's terminal then forwards a real <S-CR>
-- as CSI 13;2u, which Claude reads as "newline". A map that feeds <Esc><CR>
-- breaks this: in kitty mode <Esc> is encoded as its own key (CSI 27u), so the
-- child sees Escape followed by Enter, and Enter submits.

-- Ctrl+V pastes the system clipboard. Neovide hands nvim the raw chord, so
-- without these mappings "paste" silently does visual-block / insert-literal
-- instead. A terminal normally translates Ctrl+V into a paste event before
-- nvim ever sees it -- but only for text: Windows Terminal's paste action
-- can't paste an image, and the chord then falls through to nvim, so on WSL
-- the terminal-mode mapping is installed too to handle the image case.
-- Normal mode is left alone (blockwise visual is worth more than a paste key
-- there), and insert-literal remains on the builtin synonym <C-q>.
local is_wsl = vim.fn.has("wsl") == 1
if vim.g.neovide then
  map({ "i", "c" }, "<C-v>", "<C-r>+", { desc = "Paste clipboard" })
end
if vim.g.neovide or is_wsl then
  -- Terminal mode: text goes through nvim_paste so the pty gets one proper
  -- bracketed paste; an image is left to the program inside -- forward the
  -- raw chord and let it read the clipboard itself (Claude Code does, via
  -- osascript / wl-paste). On WSL that read would go through WSLg's clipboard
  -- bridge, which only offers image/bmp (Claude Code wants PNG) and has
  -- segfaulted weston on image transfers -- so first re-copy the image from
  -- the Windows clipboard into the Linux one as PNG via interop; wl-copy then
  -- serves wl-paste locally, without the bridge.
  local mirror_image_to_wayland = table.concat({
    [[out=$(powershell.exe -NoProfile -Command ']]
      .. [[Add-Type -AssemblyName System.Windows.Forms;]]
      .. [[$i=[Windows.Forms.Clipboard]::GetImage();]]
      .. [[if ($i) { $ms=New-Object IO.MemoryStream;]]
      .. [[$i.Save($ms,[Drawing.Imaging.ImageFormat]::Png);]]
      .. [[[Convert]::ToBase64String($ms.ToArray()) }' | tr -d '\r')]],
    [[[ -n "$out" ] || exit 1]],
    -- wl-copy forks a daemon to serve the selection; without the redirects it
    -- inherits this pipeline's stdout/stderr and vim.system waits on those
    -- pipes forever -- the on-exit callback (which forwards the paste chord)
    -- would never fire.
    [[printf %s "$out" | base64 -d | wl-copy -t image/png >/dev/null 2>&1]],
  }, "\n")
  map("t", "<C-v>", function()
    -- getreg throws on some providers when the clipboard holds an image and
    -- returns raw image bytes on others; util/clipboard sorts out both.
    local ok, text = pcall(vim.fn.getreg, "+")
    if ok and require("util.clipboard").is_text(text) then
      vim.api.nvim_paste(text, true, -1)
      return
    end
    local chan = vim.bo.channel
    if not is_wsl then
      vim.api.nvim_chan_send(chan, "\22")
      return
    end
    vim.system({ "sh", "-c", mirror_image_to_wayland }, {}, function()
      -- Forward the chord whether or not an image was found: the inner
      -- program should still see its paste key on a merely-empty clipboard.
      vim.schedule(function()
        vim.api.nvim_chan_send(chan, "\22")
      end)
    end)
  end, { desc = "Paste clipboard" })
end

-- Clear search highlight
map("n", "<Esc>", "<cmd>nohlsearch<cr>")

-- Save
map({ "n", "i" }, "<C-s>", "<cmd>w<cr>", { desc = "Save file" })

-- Reload current file from disk (checks for on-disk changes). Not under
-- <leader>r: that prefix is the review namespace (triage/nitpick).
map("n", "<leader>R", "<cmd>checktime<cr>", { desc = "Reload file from disk" })

-- Spell check is on by default in prose filetypes (see config/autocmds.lua);
-- this toggles it per-window, either to silence it in a quote-heavy paragraph
-- or to turn it on in a buffer that isn't a recognised prose filetype.
map("n", "<leader>s", function()
  vim.wo.spell = not vim.wo.spell
  vim.notify("Spell check " .. (vim.wo.spell and "on" or "off"))
end, { desc = "Toggle spell check" })

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
-- Straight to this workspace's greeter (config/greeter.lua), which is the
-- leftmost buffer tab. Reachable by clicking it or cycling <S-h> off the left
-- end too; this is the one that doesn't depend on how many buffers are in the
-- way. Builds the greeter if this workspace hasn't shown one yet.
map("n", "<leader>h", function()
  require("config.greeter").focus()
end, { desc = "Go to workspace overview" })
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
-- The greeter's todo split on demand, in any tab (config/todo.lua); next to checkmate's <leader>T keys.
map("n", "<leader>TT", function()
  require("config.todo").toggle(require("config.todo").FILE)
end, { desc = "Toggle todo list" })

-- Workspaces: one project per tabpage (see config/workspace.lua). <leader>t is
-- "tab"; the test namespace moved to <leader>T (neotest.lua) since these are
-- reached far more often.
--
-- <M-N>: switch to workspace N -- its stable number, shown on the tab label --
-- mirroring fishmonger's <C-b>N for terminals, a chord shorter for the bigger
-- jump. Bound in terminal mode too, since that is where switching mostly
-- starts from (gt/gT need normal mode first); the program in the terminal
-- never sees Alt+digit, which neither fish nor Claude Code uses.
for n = 1, 9 do
  map({ "n", "i", "x", "t" }, "<M-" .. n .. ">", function()
    require("config.workspace").switch(n)
  end, { desc = "Switch to workspace " .. n })
end
-- <M-b>: the workspace prefix -- fishmonger's <C-b> terminal keys with Alt
-- instead of Ctrl (N switch, c new, & close, .N renumber), plus w / b / e for
-- the other ways into a new workspace (a branch's worktree, a new branch's
-- worktree, a browsed-to directory). In terminal mode it takes fish's alt-b
-- (back a word) from the shell; ctrl-left does the same.
map({ "n", "i", "x", "t" }, "<M-b>", function()
  require("config.workspace").prefix()
end, { desc = "Workspace prefix (N switch / c new / & close / .N renumber / w worktree / b new branch / e browse)" })
map("n", "<leader>tn", function()
  require("config.workspace").pick_new()
end, { desc = "New project tab (recent/dev)" })
-- The other way into a worktree tab: from the PRs that actually need my review
-- in this repo, opened in review mode. <leader>r because it's where a review
-- starts; triage/nitpick own the rest of that namespace. See util/reviewqueue.lua.
map("n", "<leader>rq", function()
  require("util.reviewqueue").pick()
end, { desc = "Review queue (PRs needing my review)" })
-- The reverse: my own open PRs, by what they're waiting on me for (fix, merge)
-- or on others for (queue, reviewers).
map("n", "<leader>rm", function()
  require("util.reviewqueue").pick("mine")
end, { desc = "My PRs (to fix / merge / queued)" })
map("n", "<leader>tt", function()
  require("config.workspace").pick()
end, { desc = "Switch to open project tab" })
-- :tabclose, but named alongside the others. fishmonger shuts that tabpage's
-- terminals down with it (nothing could reach them afterwards), so this ends the
-- workspace's shells too -- hence the confirm when an agent there is live.
-- Mirrors <leader>x for a buffer; <M-b>& is the same thing.
map("n", "<leader>tx", function()
  require("config.workspace").close()
end, { desc = "Close project tab" })

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

-- gf/gF: the builtins, opened in the main editor window instead of the current
-- one, so they work from the terminal (jump to a path a program printed; enter
-- terminal-normal mode first with <C-n>). From a panel, the builtin <C-w>f/<C-w>F
-- does all the parsing into a split, which is then folded into the main window,
-- so name and line resolution is exactly nvim's.
local function goto_file_main(key)
  local count = vim.v.count > 0 and tostring(vim.v.count) or ""
  if require("config.windows").is_editor_window(0) then
    vim.cmd("normal! " .. count .. "g" .. key)
    return
  end
  local ok, err = pcall(vim.cmd, "normal! " .. count .. "\23" .. key)
  if not ok then
    vim.notify((err:gsub("^Vim%(%a+%):", "")), vim.log.levels.ERROR)
    return
  end
  local buf, cursor = vim.api.nvim_get_current_buf(), vim.api.nvim_win_get_cursor(0)
  vim.cmd("close")
  goto_main_window()
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_cursor(0, cursor)
end
map("n", "gf", function()
  goto_file_main("f")
end, { desc = "Goto file under cursor (main window)" })
map("n", "gF", function()
  goto_file_main("F")
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

--- The open file's path relative to cwd, with `:line` (or `:first-last`) when
--- lines are given. Nil, with a warning, for a buffer that isn't a file.
local function file_ref(first, last)
  local path = vim.fn.expand("%:.")
  if path == "" then
    vim.notify("no file in this buffer", vim.log.levels.WARN)
    return nil
  end
  if first and last and first ~= last then
    return ("%s:%d-%d"):format(path, math.min(first, last), math.max(first, last))
  elseif first then
    return ("%s:%d"):format(path, first)
  end
  return path
end

-- Yank the current (open) file's path, without a trip to the explorer.
-- <leader>yf ("yank file"): path relative to cwd. <leader>yl: with the cursor
-- line as path:line, so it round-trips straight back through gf / <leader>o.
-- Register-aware like the other path commands: `"a<leader>yf` yanks into register
-- a; bare uses the unnamed register, which defaults to + (clipboard) here.
local function yank_file_path(with_line)
  local path = file_ref(with_line and vim.api.nvim_win_get_cursor(0)[1] or nil)
  if not path then
    return
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

-- <leader>ya ("yank to agent"): <leader>yl's path:line, typed straight into the
-- side terminal's prompt (fishmonger.send) and left unsubmitted, so you write
-- your comment on that line to the agent right there. From visual mode the
-- selection's lines go as path:first-last. No register is touched.
map({ "n", "x" }, "<leader>ya", function()
  local first, last = vim.fn.line("."), nil
  if vim.fn.mode():match("^[vV\22]") then
    last = vim.fn.line("v")
    vim.cmd("normal! \27") -- leave visual so the terminal opens in a clean state
  end
  local ref = file_ref(first, last)
  if ref then
    require("fishmonger").send(ref .. " ")
  end
end, { desc = "Send path:line to the side terminal (agent)" })

map("n", "<leader>N", function()
  vim.wo.relativenumber = not vim.wo.relativenumber
end, { desc = "Toggle relative line numbers" })
