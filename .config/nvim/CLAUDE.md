# Neovim config

Personal Neovim config, tracked in the bare dotfiles repo at `~/.dotfiles`
(work tree `$HOME`). Stage changes with `dotfiles add`, not plain `git add` —
see `~/README.md`.

## Tests

There is a test suite. **Run it after changing anything under `lua/`:**

```bash
cd ~/.config/nvim && make test
```

It runs headless via plenary's busted harness and exits non-zero on failure.
A single file: `make test FILE=tests/terms_spec.lua`.

Specs live in `tests/*_spec.lua` and cover the pure logic worth pinning:

| Spec                | Covers                                                      |
| ------------------- | ----------------------------------------------------------- |
| `review_spec.lua`   | `review.verdict` rollup, `status`/`folder` path lookups      |
| `terms_spec.lua`    | side-terminal slot table: show/new/move/toggle               |
| `ide_spec.lua`      | side-terminal width, the 80-column floor, explorer geometry  |
| `comments_spec.lua` | `rebuild_marked` decorator set over comments + drafts        |

`tests/minimal_init.lua` loads this config plus plenary, and deliberately does
**not** load lazy.nvim — no plugin `config()` runs. A spec that needs a plugin
object fakes it: `terms_spec.lua` preloads `package.loaded["toggleterm.terminal"]`
with a stub Terminal, since the real one wants a pty.

Two traps when writing specs:

- Require `luassert` explicitly (`local assert = require("luassert")`). Relying
  on the busted global shadows Lua's builtin `assert` and confuses lua_ls.
- When stubbing a `vim.*` function, keep its real arity. A narrower stub
  retrains lua_ls's inferred signature across the whole config, which then
  reports every real call site as passing too many arguments.

Anything needing a live pty, a git repo, or the GitHub API is left untested on
purpose — mocking it would test the mock. That's why `thread_at_cursor` and the
`gh` paths in `review/comments.lua` have no spec.

## Layout

- `lua/config/` — options, keymaps, autocmds, and the IDE-mode machinery.
  `ide.lua` is the single source of truth for "IDE mode vs text-editor mode"
  and the window geometry that follows; `terms.lua` owns the tmux-style tab
  strip over the side terminal.
- `lua/plugins/` — one file per plugin, lazy.nvim specs.
- `lua/review/` — a PR review mode: triage state on the tree (`init.lua`) plus
  inline GitHub line comments and drafts (`comments.lua`).

The side terminal runs shells directly in an nvim terminal buffer. There is no
tmux backend; `terms.lua` reimplements tmux's window semantics (`<C-b>` prefix,
hidden-but-alive tabs, `move-window`) natively.

## Conventions

- `stylua` formats Lua on save via conform, configured by `stylua.toml`. Keep
  that file — stylua's *default* is tab indent, and without it a save silently
  reformats a whole file away from the 2-space style used here.
- `.luarc.json` declares the `vim` global and the busted globals. Keep it in
  sync when adding test globals, so lua_ls stays clean outside nvim (CI, a bare
  `lua-language-server`) and not just via the in-editor `lsp.lua` settings.
- Comments explain *why*, and state constraints the code can't. Don't add
  comments describing code that used to be there.
