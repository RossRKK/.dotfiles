# Cheatsheet

## Contents

- [Editing](#editing) — modes · movement · editing · surround · search · splits & buffers
- [Navigation](#navigation) — `g` go-to · `]`/`[` next/prev · Flash jumps
- [Find and lists](#find-and-lists) — `Space+f` find · `Space+l` Trouble
- [Code and diagnostics](#code-and-diagnostics) — `Space+c` action · `Space+rn` rename · `Space+d` diagnostics · `Space+u` undo
- [Tests and debugging](#tests-and-debugging) — `Space+t` neotest · dap debug
- [Git](#git) — `Space+g` hunks · merge conflicts
- [Branch review](#branch-review) — review mode · PR comments
- [File explorer](#file-explorer) — neo-tree keys · git glyphs · review indicators
- [Terminal](#terminal) — side terminal · tabs
- [Fish](#fish) — fzf.fish pickers · autopair
- [tmux](#tmux)
- [dotfiles](#dotfiles)

---

## Editing

### Modes

| Key       | Action                 |
| --------- | ---------------------- |
| `i`       | Insert before cursor   |
| `a`       | Insert after cursor    |
| `o` / `O` | New line below / above |
| `v`       | Visual mode            |
| `V`       | Visual line mode       |
| `Ctrl+Q`  | Visual block mode      |

### Movement

| Key                 | Action                     |
| ------------------- | -------------------------- |
| `h j k l`           | Left / down / up / right   |
| `w` / `b`           | Next / prev word           |
| `0` / `$`           | Start / end of line        |
| `gg` / `G`          | Top / bottom of file       |
| `Ctrl+U` / `Ctrl+D` | Scroll half page up / down |
| `Ctrl+O` / `Ctrl+I` | Jump back / forward        |

### Editing

| Key               | Action                                 |
| ----------------- | -------------------------------------- |
| `ciw`             | Change word                            |
| `ci(` `ci"` `ci{` | Change inside parens / quotes / braces |
| `dd` / `yy`       | Delete / yank (copy) line              |
| `p` / `P`         | Paste below / above                    |
| `u` / `Ctrl+R`    | Undo / redo                            |
| `Ctrl+S`          | Save                                   |
| `Space+R`         | Reload file from disk                  |
| `.`               | Repeat last change                     |

### Surround (nvim-surround)

| Key             | Action                                        |
| --------------- | --------------------------------------------- |
| `ysiw"`         | Wrap word in quotes                           |
| `ysiw)` `ysiw}` | Wrap word in parens / braces (no inner space) |
| `ysiw(` `ysiw{` | Wrap word in parens / braces (inner space)    |
| `yss)`          | Wrap whole line in parens                     |
| `S)` (visual)   | Wrap selection in parens                      |
| `cs"'`          | Change surrounding `"` to `'`                 |
| `ds"`           | Delete surrounding quotes                     |

### Search

| Key       | Action                 |
| --------- | ---------------------- |
| `/`       | Search forward         |
| `n` / `N` | Next / prev match      |
| `Esc`     | Clear search highlight |

### Splits & Buffers

| Key                   | Action                                      |
| --------------------- | ------------------------------------------- |
| `:vsp`                | Vertical split                              |
| `:sp`                 | Horizontal split                            |
| `Ctrl+H/L/J/K`        | Move between splits (works in terminal too) |
| `:vert res 80`        | Resize vertical split to 80 columns         |
| `Shift+L` / `Shift+H` | Next / prev buffer                          |
| `Space+x`             | Close buffer                                |
| `Space+.`             | Toggle scratch buffer (per project)         |
| `Space+S`             | Pick among all scratch buffers              |

### Layout (edgy)

The IDE layout is pinned by [edgy](https://github.com/folke/edgy.nvim): explorer +
outline on the **left**, the side terminal on the **right**, the editor in the
middle. edgy sets each panel's *opening* size, then tracks whatever you resize
it to — so drags, `Ctrl+w` splits, and the arrow keys below all stick (after a
brief warm-up on open). Keys work while focused inside an edge window (explorer,
outline, terminal):

| Key                     | Action                                  |
| ----------------------- | --------------------------------------- |
| `Ctrl+Right` / `Ctrl+Left` | Grow / shrink the edge's width       |
| `Ctrl+Up` / `Ctrl+Down`    | Grow / shrink height (stacked panels)|
| `Space+wr`                 | Reset all panels to opening sizes    |
| `]w` / `[w`                | Next / prev window in the edgebar    |
| `Q`                        | Close the whole edgebar              |

Because edgy follows resizes now, neo-tree's `e` (auto-expand-width, fit the
longest name) works again — it no longer fights the panel width. `Space+wr`
switches auto-expand back off as it resets.

Notifications use the snacks notifier (toasts, top-right); `Space+n` opens the
scrollback history of everything that was notified.

---

## Navigation

### g — Go somewhere

| Key  | Action                                   |
| ---- | ---------------------------------------- |
| `gd` | Go to definition                         |
| `gi` | Go to implementation                     |
| `gr` | Go to references                         |
| `gf` / `gF` | Native goto-file under cursor, opened in the **main window** — the *only* difference from the builtins. `gF` also jumps to a trailing line (`foo.rs:42`). Works from the terminal (enter terminal-normal mode with `Ctrl+N` first): jump to a path a program printed |
| `Space+o` | Open the path in a register in the main window (`"a Space+o` for register a; bare = clipboard) |
| `Space+yf` | Yank the open **file's** path (jumps back via `gf` / `Space+o`) |
| `Space+yl` | Yank the open file's `path:line` at cursor |
| `K`  | Hover docs                               |

The file-path yanks (`Space+yf` / `Space+yl`) and `Space+o` are register-aware:
prefix `"a` to target register a — e.g. `"a Space+yf` yanks a path into register
a, then `"a Space+o` opens it. Bare (no prefix) uses the clipboard.

To yank a path out of *buffer text* (a path printed in the terminal, a diff, a
log) just use a native text object: `yiW` for a bare token, `yi(` for one
wrapped like `Read(src/foo.rs)`.

### ] / [ — Next / prev

| Key         | Action                 |
| ----------- | ---------------------- |
| `]d` / `[d` | Next / prev diagnostic |
| `]h` / `[h` | Next / prev git hunk   |
| `]i` / `[i` | Jump to bottom / top edge of the current scope (snacks) |

`]i` / `[i` shadow the builtins that echo the first line containing the keyword
under the cursor — an accepted trade-off. The scope also gives text objects:
`ii` / `ai` (operator/visual) select the current indent/treesitter scope.

### Flash — jump anywhere

| Key           | Action                                        |
| ------------- | --------------------------------------------- |
| `s{chars}`    | Jump to any visible match (labels appear; press the label) |
| `S`           | Select by treesitter node (expand with repeats) |
| `r` (op-pend) | "Remote" — e.g. `yr{jump}` yanks elsewhere without moving |
| `f`/`t`/`/`   | Enhanced with jump labels automatically       |

`s` shadows Vim's substitute — use `cl` (char) / `cc` (line) for that.

---

## Find and lists

### Space+f — Find

| Key        | Action                   |
| ---------- | ------------------------ |
| `Ctrl+P`   | Find files               |
| `Space+fg` | Live grep across project |
| `Space+fd` | Live grep in the current file's directory |
| `Space+fb` | Find open buffers        |
| `Space+fs` | Symbols in current file (LSP) |
| `Space+fw` | Symbols across workspace (LSP, live) |
| `Space+ft` | List TODO / FIXME / … comments (Trouble) |
| `Space+fr` | Project find **& replace** (grug-far) |
| `Space+fh` | Help tags                |

The finder is the [snacks picker](https://github.com/folke/snacks.nvim) (input on
top, preview on the right); it also backs `vim.ui.select`, so selection prompts
(e.g. branch-review menus) use the same UI.

`Space+fs` / `Space+fw` search LSP *symbols* (functions, types, …) rather than
text — the "Go to Symbol" analogues. `fw` re-queries the language server on each
keystroke, so it needs an LSP attached (e.g. rust-analyzer on a `.rs` file).

`Space+fr` opens a ripgrep search in an editable buffer: type a search + a
replacement, preview matches, apply across the whole project (regex + capture
groups supported).

### Space+l — Lists (Trouble)

| Key        | Action                              |
| ---------- | ----------------------------------- |
| `Space+ld` | Workspace diagnostics               |
| `Space+lD` | Current-buffer diagnostics          |
| `Space+lr` | LSP references                      |
| `Space+ls` | Document symbols                    |
| `Space+ll` | LSP definitions / refs / impls      |
| `Space+lq` | Quickfix list                       |
| `Space+lt` | TODO comments                       |

---

## Code and diagnostics

### Space+c — Code

| Key        | Action      |
| ---------- | ----------- |
| `Space+ca` | Code action |

### Space+rn — Rename

| Key        | Action        |
| ---------- | ------------- |
| `Space+rn` | Rename symbol |

### Space+d — Diagnostics

| Key       | Action                |
| --------- | --------------------- |
| `Space+d` | Show diagnostic popup |

### Space+u — Undo tree

| Key       | Action                                          |
| --------- | ----------------------------------------------- |
| `Space+u` | Toggle the undo-tree panel (branching history)  |

Undo is persisted to disk (`undofile`), so the tree survives restarts.

---

## Tests and debugging

### Space+t — Tests (neotest)

| Key        | Action                       |
| ---------- | ---------------------------- |
| `Space+tr` | Run nearest test             |
| `Space+tf` | Run all tests in the file    |
| `Space+td` | Debug nearest test (via dap) |
| `Space+tt` | Toggle the summary tree      |
| `Space+to` | Show output of the last test |
| `Space+tO` | Toggle the output panel      |
| `Space+ts` | Stop a running test          |

Pass/fail signs render in the gutter; driven by rust-analyzer runnables.

### Debug (nvim-dap)

| Key        | Action                 |
| ---------- | ---------------------- |
| `F5`       | Start / continue       |
| `F10`      | Step over              |
| `F11`      | Step into              |
| `F12`      | Step out               |
| `Space+b`  | Toggle breakpoint      |
| `Space+B`  | Conditional breakpoint |
| `Space+du` | Toggle debug UI        |

---

## Git

### Space+g — Git hunks (gitsigns)

| Key        | Action                    |
| ---------- | ------------------------- |
| `Space+gd` | Toggle inline diff vs HEAD (in-buffer, no split) |
| `Space+gp` | Preview hunk              |
| `Space+gs` | Stage hunk                |
| `Space+gr` | Reset hunk                |
| `Space+gb` | Blame current line (popup) |
| `Space+gB` | Toggle inline blame       |
| `Space+gt` | Swap explorer to the git status view |
| `Space+ghi` | Browse GitHub issues (snacks picker + `gh` CLI) |
| `Space+ghp` | Browse GitHub PRs (snacks picker + `gh` CLI) |

`Space+gt` swaps the explorer's top pane to neo-tree's `git_status` source (and
back) — a changed-files list where you stage / commit per file:

| Key  | Action                          |
| ---- | ------------------------------- |
| `ga` | Stage the file                  |
| `gu` | Unstage the file                |
| `gt` | Toggle staged / unstaged        |
| `gr` | Revert (discard changes)        |
| `gc` | Commit                          |
| `gp` | Push                            |
| `gg` | Commit **and** push             |
| `gU` | Undo last commit                |

(These overlap with lazygit at `Ctrl+G` and gitsigns hunk staging above — use
whichever fits.)

Inline blame (dimmed, at end of the current line) is on by default; `Space+gB`
toggles it off/on.

### Merge conflicts (git-conflict.nvim)

Resolve conflicts **in place** in the current buffer — no 3-way diff splits, so
the window layout never moves. The plugin highlights the ours/theirs regions and
suppresses LSP diagnostics on the marker lines while a file is conflicted.
Staging / committing lives in lazygit (`Ctrl+G`).

Maps are buffer-local and only live while the file is conflicted.

| Key         | Action                     |
| ----------- | -------------------------- |
| `Space+cc`  | Keep **this one** (side under cursor) |
| `Space+co`  | Keep **ours** (HEAD)       |
| `Space+ct`  | Keep **theirs** (incoming) |
| `Space+cb`  | Keep **both**              |
| `Space+c0`  | Keep **neither**           |
| `]x` / `[x` | Next / prev conflict       |

---

## Branch review

### Review mode (Space+r)

Highlights what merging this branch into the default branch would actually
change (the merge-result diff): gitsigns marks changed lines in the sign column,
and the explorer flags changed files. Changes the default branch already has —
even if the branch made them independently — don't show. Off by default; turn it
on per-branch with `Space+rt` and approve / reject files as you go.

The target defaults to the auto-detected default branch (`origin/HEAD`, else
`main` / `master`). Override it with `Space+rb` (or `:ReviewBase <branch>`, with
branch-name completion); an empty value clears back to auto-detect.

| Key        | Action                                     |
| ---------- | ------------------------------------------ |
| `Space+rr` | Mark file / folder (recursive) approved    |
| `Space+rj` | Mark file / folder rejected (flag)         |
| `Space+ru` | Clear decision (untriage)                  |
| `Space+rt` | Toggle review mode on / off                |
| `Space+rb` | Set the target branch (empty = auto-detect) |
| `Space+rd` | Toggle inline diff of current file vs base |
| `Space+rR` | Refresh review status                      |

`Space+rr` / `Space+rj` / `Space+ru` act on the node under the cursor in the
explorer, otherwise the current buffer. An approved file flips back to "changed"
if it's edited again; a rejected file becomes "revised" when edited (the flag
was acted on — re-review the fix) rather than losing the flag.

`Space+rd` overlays a combined inline diff on the file itself — deleted lines
shown inline, added / changed lines highlighted — against the review base
(default branch tip), instead of a side-by-side split. Works whether or not
review mode is on; it's a global mode, so it applies to all buffers until
toggled off.

### PR comments (batched review)

With review mode on, drop line comments in your normal buffers. New comments
queue as **local drafts** (rendered inline in a dimmer hue) rather than posting
one-by-one, so a whole pass goes out as a single GitHub review — no
notification per line. Everyone's comments render inline; yours-in-waiting sit
alongside them.

| Key        | Action                                                    |
| ---------- | --------------------------------------------------------- |
| `]r` / `[r` | Jump to next / prev PR comment                           |
| `Space+rc` | Draft a comment on the line (or visual range)             |
| `Space+re` | Edit the comment / draft on the line (asks if several)    |
| `Space+ra` | Reply to the comment thread on the line (posts now)       |
| `Space+rx` | Discard the draft on the line                             |
| `Space+rS` | Submit all drafts as one review                           |
| `Space+rC` | Refresh PR comments from GitHub                           |
| `Space+ro` | Toggle showing outdated comments (anchor line gone)       |
| `Space+rs` | Toggle showing resolved-thread comments                   |

Submit infers the verdict from the triage rollup — no picking: any live
rejection → **request changes**, all approved → **approve**, anything still
untriaged → **comment**. So an early submit goes out as a plain comment batch,
and only firms up to approve/request-changes once nothing's pending. A compose
float shows the verdict in its title and takes an optional summary (`Ctrl+S`
sends even when empty, `q` cancels); a bare approval with no summary defaults to
"LGTM". Drafts clear on a successful submit, so continuing the review starts a
fresh batch. Replies and edits to already-posted comments still go out
immediately.

Outdated comments (GitHub dropped their anchor line) show by default, tagged
`(outdated)`; resolved-thread comments are hidden by default. Toggle each with
`Space+ro` / `Space+rs`. The review-mode status string (top-left) shows the
target branch and which comment categories are currently on show.

---

## File explorer

The left column stacks two neo-tree windows: the file tree on top and a symbols
outline (`document_symbols`) below it — a live, LSP-driven tree of the focused
file's functions / types you can jump through. All keys in the sub-tables below
are inside the tree; `?` shows the full, live list.

| Key       | Action                          |
| --------- | ------------------------------- |
| `Space+e` | Toggle explorer + outline       |
| `Space+v` | Reveal current file in explorer |

**Open & navigate**

| Key             | Action                               |
| --------------- | ------------------------------------ |
| `Enter` / click | Open file / expand folder            |
| `S` / `s`       | Open in horizontal / vertical split  |
| `t`             | Open in a new tab                    |
| `w`             | Open via the window picker           |
| `P`             | Toggle a floating preview of the file |
| `C` / `z`       | Collapse this node / all nodes       |
| `e`             | Toggle auto-expand width (fit longest name) |
| `.` / `<BS>`    | Set tree root here / go up a level   |
| `R`             | Refresh the tree                     |

**Search & filter**

| Key      | Action                                              |
| -------- | --------------------------------------------------- |
| `/`      | Fuzzy filter the tree (live; `Esc` to keep, `C-x` clears) |
| `#`      | Fuzzy *sort* (fzy) without hiding non-matches       |
| `D`      | Fuzzy filter within a chosen directory              |
| `f`      | Filter on submit (type, `Enter` to apply)           |
| `C-x`    | Clear an active filter                              |

In the filter popup, `C-n`/`C-p` (or ↓/↑) move through matches, `S-Enter` keeps
the filter after selecting, `C-Enter` selects and clears it.

**File operations**

| Key       | Action                                    |
| --------- | ----------------------------------------- |
| `a` / `A` | Add file (trailing `/` = dir) / add dir   |
| `r` / `b` | Rename / rename just the basename         |
| `d`       | Delete                                     |
| `c` / `m` | Copy / move (prompts for destination)      |
| `y` / `x` | Copy / cut the file to neo-tree's clipboard |
| `p`       | Paste clipboard here (`C-r` clears it)     |
| `i`       | Show file details (size, times, perms)     |

**Copy a path to the system clipboard** (custom — `y` above copies the *file*):

| Key  | Copies                          |
| ---- | ------------------------------- |
| `gy` | Path relative to the cwd        |
| `gY` | Absolute path                   |

**Git, ordering & sources**

| Key          | Action                                            |
| ------------ | ------------------------------------------------- |
| `]g` / `[g`  | Jump to next / prev git-modified file             |
| `o` then …   | Order by: `c`reated `d`iagnostics `g`it `m`odified `n`ame `s`ize `t`ype |
| `H`          | Toggle hidden / gitignored files                  |
| `<` / `>`    | Previous / next source (files ↔ symbols)          |
| `?` / `q`    | Show all mappings / close the window              |

### Explorer git status glyphs

| Glyph | Meaning             |
| ----- | ------------------- |
| `M`   | Modified (unstaged) |
| `✓`   | Staged              |
| `?`   | Untracked           |
| `D`   | Deleted             |
| `R`   | Renamed             |
| `U`   | Unmerged (conflict) |
| `◌`   | Ignored             |

### Explorer review indicators

| Glyph | Meaning                                                                   |
| ----- | ------------------------------------------------------------------------- |
| `●`   | Changed on this branch, not yet triaged                                   |
| `✓`   | Approved and unchanged since                                              |
| `✗`   | Rejected / flagged, unchanged since                                       |
| `↻`   | Was rejected, then edited — re-review the fix                             |
| 💬    | Has PR comments or unsent drafts (review mode on)                         |

Folders show the highest-priority child status, ordered by what needs *your*
attention: revised > changed > rejected > approved. So a folder surfaces work
still to do (won't read as done while it holds changed/revised files), an open
flag (rejected) outranks a clean `✓`, and it only shows `✓` once every changed
file under it is approved.

---

## Terminal

Terminals run natively in nvim buffers — full vim normal mode over real
scrollback, and Claude Code renders cleanly (nvim 0.12+ fixed the TUI munging).

| Key                    | Action                                                |
| ---------------------- | ----------------------------------------------------- |
| `Ctrl+T`               | Toggle the side terminal                              |
| `Ctrl+G`               | Toggle the git TUI — jjui in a jj repo, else lazygit  |
| `Ctrl+Shift+G`         | Open the git TUI in a picked project                  |
| `Ctrl+N` (in terminal) | Enter terminal-normal mode (then `gf` jumps to a ref) |
| `<leader>y` (visual, side terminal) | Yank the selection joined into one line — for wrapped commands in Claude Code output (pty soft-wraps in shell output join automatically on any yank) |

**lazygit copy-to-clipboard:** `Ctrl+O` copies the selected item — branch name in
the branches panel, commit SHA in the commits panel, path in the files panel. In
the commits panel `y` opens a menu to pick which attribute (hash / subject /
author / …).

### Terminal tabs

tmux-style tabs in the side terminal: one fills the slot, the others stay alive
but hidden. Switch from **terminal-normal mode** (enter it with `Ctrl+N`), then
press the `Ctrl+B` binding. `Ctrl+T` toggles the terminal from anywhere. A
titled tab strip shows across the top when the side terminal is open.

| Key           | Action                                            |
| ------------- | ------------------------------------------------- |
| `Ctrl+B 1-9`  | Switch to tab N (creates it on demand)            |
| `Ctrl+B c`    | New tab in the next free slot                     |
| `Ctrl+B &`    | Kill the current tab                              |
| `Ctrl+B . N`  | Move the current tab to slot N (`.` then `1-9`)   |
| `Ctrl+T`      | Toggle the side terminal                          |

---

## Fish

### fzf.fish — fuzzy pickers

Fuzzy-search pickers ([fzf.fish](https://github.com/PatrickF1/fzf.fish)) that
insert the selection into the command line. Inside any picker: type to filter,
`Tab` multi-selects, `Enter` inserts, `Esc` cancels; a preview pane shows file
contents / diffs / values.

| Key          | Search                                        |
| ------------ | --------------------------------------------- |
| `Ctrl+R`     | Command history                               |
| `Ctrl+Alt+F` | Files & directories (recursive from cwd)      |
| `Ctrl+Alt+L` | Git log (preview shows the commit)            |
| `Ctrl+Alt+S` | Git status (preview shows the diff)           |
| `Ctrl+V`     | Shell variables (preview shows the value)     |
| `Ctrl+Alt+P` | Processes (inserts the PID)                   |

### autopair

Typing `(` `[` `{` `"` `'` auto-inserts the closer and leaves the cursor
between; backspace deletes an empty pair, and typing the closer skips over an
existing one.

---

## tmux

Prefix = `Ctrl+B`.

### Windows

| Key                     | Action                   |
| ----------------------- | ------------------------ |
| `Ctrl+B c`              | New window               |
| `Ctrl+B n` / `Ctrl+B p` | Next / prev window       |
| `Ctrl+B 1-9`            | Jump to window by number |
| `Ctrl+B ,`              | Rename window            |
| `Ctrl+B &`              | Close window             |

### Panes

| Key                 | Action                        |
| ------------------- | ----------------------------- |
| `Ctrl+B %`          | Split vertically              |
| `Ctrl+B "`          | Split horizontally            |
| `Ctrl+B arrow keys` | Move between panes            |
| `Ctrl+B x`          | Close pane                    |
| `Ctrl+B z`          | Zoom pane (toggle fullscreen) |

### Session

| Key           | Action              |
| ------------- | ------------------- |
| `Ctrl+B d`    | Detach session      |
| `Ctrl+B r`    | Reload tmux config  |
| `tmux attach` | Reattach to session |

### Scroll

| Key        | Action            |
| ---------- | ----------------- |
| `Ctrl+B [` | Enter scroll mode |
| `q`        | Exit scroll mode  |

---

## dotfiles

```fish
dotfiles status
dotfiles add ~/.config/nvim/lua/plugins/foo.lua
dotfiles commit -m "message"
dotfiles push
```
