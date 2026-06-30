# Cheatsheet

## tmux (prefix = `Ctrl+B`)

### Windows
| Key | Action |
|-----|--------|
| `Ctrl+B c` | New window |
| `Ctrl+B n` / `Ctrl+B p` | Next / prev window |
| `Ctrl+B 0-9` | Jump to window by number |
| `Ctrl+B ,` | Rename window |
| `Ctrl+B &` | Close window |

### Panes
| Key | Action |
|-----|--------|
| `Ctrl+B %` | Split vertically |
| `Ctrl+B "` | Split horizontally |
| `Ctrl+B arrow keys` | Move between panes |
| `Ctrl+B x` | Close pane |
| `Ctrl+B z` | Zoom pane (toggle fullscreen) |

### Session
| Key | Action |
|-----|--------|
| `Ctrl+B d` | Detach session |
| `Ctrl+B r` | Reload tmux config |
| `tmux attach` | Reattach to session |

### Scroll
| Key | Action |
|-----|--------|
| `Ctrl+B [` | Enter scroll mode |
| `q` | Exit scroll mode |

---

## Neovim

### My keymaps
| Key | Action |
|-----|--------|
| `Ctrl+S` | Save |
| `Ctrl+P` | Fuzzy file find |
| `Space+e` | Toggle file explorer |
| `Space+g` | Git status in explorer |
| `Ctrl+T` | Toggle terminal |
| `Ctrl+H/J/K/L` | Move between splits |
| `jk` | Exit insert mode |

### LSP
| Key | Action |
|-----|--------|
| `gd` | Go to definition |
| `gr` | Go to references |
| `K` | Hover docs |
| `Space+ca` | Code action |
| `Space+rn` | Rename symbol |
| `Space+d` | Show diagnostic |
| `[d` / `]d` | Prev / next diagnostic |

### Movement
| Key | Action |
|-----|--------|
| `w` / `b` | Next / prev word |
| `0` / `$` | Start / end of line |
| `gg` / `G` | Top / bottom of file |
| `Ctrl+U` / `Ctrl+D` | Scroll half page up / down |
| `Ctrl+O` / `Ctrl+I` | Jump back / forward |

### Editing
| Key | Action |
|-----|--------|
| `i` / `a` | Insert before / after cursor |
| `o` / `O` | New line below / above |
| `ciw` | Change word |
| `ci(` `ci"` | Change inside parens / quotes |
| `dd` / `yy` | Delete / yank (copy) line |
| `p` / `P` | Paste below / above |
| `u` / `Ctrl+R` | Undo / redo |
| `gcc` | Toggle comment (line) |

### Search
| Key | Action |
|-----|--------|
| `/` | Search forward |
| `n` / `N` | Next / prev match |
| `Esc` | Clear search highlight |
| `Space+fg` | Live grep across project |

### Buffers
| Key | Action |
|-----|--------|
| `Space+fb` | Find open buffers |
| `Ctrl+^` | Toggle last buffer |
| `:bd` | Close buffer |

---

## dotfiles

```fish
dotfiles status
dotfiles add ~/.config/nvim/lua/plugins/foo.lua
dotfiles commit -m "message"
dotfiles push
```
