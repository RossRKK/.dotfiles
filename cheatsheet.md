# Cheatsheet

## Neovim

### Modes

| Key       | Action                 |
| --------- | ---------------------- |
| `i`       | Insert before cursor   |
| `a`       | Insert after cursor    |
| `o` / `O` | New line below / above |
| `jk`      | Exit insert mode       |
| `v`       | Visual mode            |
| `V`       | Visual line mode       |

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
| `Space+rf`        | Reload file from disk                  |
| `.`               | Repeat last change                     |

### Search

| Key       | Action                 |
| --------- | ---------------------- |
| `/`       | Search forward         |
| `n` / `N` | Next / prev match      |
| `Esc`     | Clear search highlight |

### Folding (treesitter)

Folds follow the code structure; files open fully expanded.

| Key         | Action                                       |
| ----------- | -------------------------------------------- |
| `zM` / `zR` | Collapse to definitions / expand everything  |
| `zm` / `zr` | Fold / unfold one more level                 |
| `za`        | Toggle fold under cursor                     |
| `zc` / `zo` | Close / open fold under cursor               |
| `zj` / `zk` | Jump to next / prev fold                     |

### Splits & Buffers

| Key                   | Action                                      |
| --------------------- | ------------------------------------------- |
| `:vsp`                | Vertical split                              |
| `:sp`                 | Horizontal split                            |
| `Ctrl+H/L/J/K`        | Move between splits (works in terminal too) |
| `:vert res 80`        | Resize vertical split to 80 columns         |
| `Shift+L` / `Shift+H` | Next / prev buffer                          |
| `Space+x`             | Close buffer                                |

### g — Go somewhere

| Key  | Action                                   |
| ---- | ---------------------------------------- |
| `gd` | Go to definition                         |
| `gi` | Go to implementation                     |
| `gr` | Go to references                         |
| `gf` | Open file under cursor (`path:line:col`; fuzzy-finder fallback) |
| `K`  | Hover docs                               |

### ] / [ — Next / prev

| Key         | Action                 |
| ----------- | ---------------------- |
| `]d` / `[d` | Next / prev diagnostic |
| `]h` / `[h` | Next / prev git hunk   |

### Space+f — Find

| Key        | Action                   |
| ---------- | ------------------------ |
| `Ctrl+P`   | Find files               |
| `Space+fg` | Live grep across project |
| `Space+fb` | Find open buffers        |
| `Space+fh` | Help tags                |

### Space+c — Code

| Key        | Action      |
| ---------- | ----------- |
| `Space+ca` | Code action |

### Space+r — Rename

| Key        | Action        |
| ---------- | ------------- |
| `Space+rn` | Rename symbol |

### Space+d — Diagnostics

| Key       | Action                |
| --------- | --------------------- |
| `Space+d` | Show diagnostic popup |

### Explorer

| Key       | Action                          |
| --------- | ------------------------------- |
| `Space+e` | Toggle file explorer            |
| `Space+v` | Reveal current file in explorer |

### Space+g — Git

| Key        | Action                                          |
| ---------- | ----------------------------------------------- |
| `Space+gd` | Diffview: uncommitted changes                   |
| `Space+gb` | Diffview: whole-branch diff (vs default branch) |
| `Space+gh` | Diffview: current file history                  |

### Space+h — Git hunks (gitsigns)

| Key        | Action                    |
| ---------- | ------------------------- |
| `Space+hd` | Diff current file vs HEAD |
| `Space+hp` | Preview hunk              |
| `Space+hs` | Stage hunk                |
| `Space+hr` | Reset hunk                |
| `Space+hb` | Blame current line        |

### Space+r — Branch review mode

Highlights what merging this branch into the default branch would actually
change (the merge-result diff): gitsigns marks changed lines in the sign column,
and the explorer flags changed files. Changes the default branch already has —
even if the branch made them independently — don't show. Off by default; turn it
on per-branch with `Space+rt` and approve / reject files as you go.

| Key        | Action                                     |
| ---------- | ------------------------------------------ |
| `Space+rr` | Mark file / folder (recursive) approved    |
| `Space+rj` | Mark file / folder rejected (flag)         |
| `Space+ru` | Clear decision (untriage)                  |
| `Space+rt` | Toggle review mode on / off                |
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

### File explorer (nvim-tree)

| Key     | Action                    |
| ------- | ------------------------- |
| `Enter` | Open file / expand folder |
| `y`     | Copy filename             |
| `Y`     | Copy relative path        |
| `gy`    | Copy absolute path        |
| `a`     | Create file               |
| `d`     | Delete file               |
| `r`     | Rename file               |

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

Folders show the highest-priority child status, ordered by what needs *your*
attention: revised > changed > rejected > approved. So a folder surfaces work
still to do (won't read as done while it holds changed/revised files), an open
flag (rejected) outranks a clean `✓`, and it only shows `✓` once every changed
file under it is approved.

### Terminal

| Key                              | Action                                                |
| -------------------------------- | ----------------------------------------------------- |
| `Ctrl+T`                         | Toggle the side terminal                              |
| `Ctrl+G`                         | Toggle lazygit (works in normal & terminal mode)      |
| `Ctrl+N` (in terminal)           | Enter terminal-normal mode (then `gf` jumps to a ref) |
| `Ctrl+B` (terminal, normal mode) | Send the tmux prefix and drop back into the terminal  |

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

## tmux (prefix = `Ctrl+B`)

### Windows

| Key                     | Action                   |
| ----------------------- | ------------------------ |
| `Ctrl+B c`              | New window               |
| `Ctrl+B n` / `Ctrl+B p` | Next / prev window       |
| `Ctrl+B 0-9`            | Jump to window by number |
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
