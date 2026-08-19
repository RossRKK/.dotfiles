# Neovim config

Personal Neovim config, tracked in the bare dotfiles repo at `~/.dotfiles`
(work tree `$HOME`). Stage changes with `dotfiles add`, not plain `git add` —
the dotfiles workflow (bare-repo clone, the `dotfiles` alias) is documented in
`~/README.md`.

User-facing keymaps and features are documented in `~/cheatsheet.md` (a broader
sheet also covering tmux and the dotfiles commands). **Keep it in sync:** when
you add, remove, or rebind a mapping here, update the matching table there.

## Tests

There is a test suite. **Run it after changing anything under `lua/`:**

```bash
cd ~/.config/nvim && make test
```

It runs headless via plenary's busted harness and exits non-zero on failure.
A single file: `make test FILE=tests/ide_spec.lua`.

Specs live in `tests/*_spec.lua` and cover the pure logic worth pinning:

| Spec             | Covers                                    |
| ---------------- | ----------------------------------------- |
| `ide_spec.lua`   | side-terminal width, explorer geometry    |

The side-terminal and branch-review logic now live in external plugins, each
with its own test suite (developed locally under `~/dev` via lazy's `dev` path):
[fishmonger.nvim](https://github.com/RossRKK/fishmonger.nvim) (the side terminal),
[triage.nvim](https://github.com/RossRKK/triage.nvim) (per-file review status +
verdict rollup), and [nitpick.nvim](https://github.com/RossRKK/nitpick.nvim)
(inline GitHub comments).

`tests/minimal_init.lua` loads this config plus plenary, and deliberately does
**not** load lazy.nvim — no plugin `config()` runs. A spec that needs a plugin
object fakes it (keeping the real arity of any stubbed `vim.*` function).

Two traps when writing specs:

- Require `luassert` explicitly (`local assert = require("luassert")`). Relying
  on the busted global shadows Lua's builtin `assert` and confuses lua_ls.
- When stubbing a `vim.*` function, keep its real arity. A narrower stub
  retrains lua_ls's inferred signature across the whole config, which then
  reports every real call site as passing too many arguments.

Anything needing a live pty, a git repo, or the GitHub API is left untested on
purpose — mocking it would test the mock.

## Layout

- `lua/config/` — options, keymaps, autocmds, and the IDE-mode machinery.
  `ide.lua` is the single source of truth for "IDE mode vs text-editor mode"
  and the window geometry that follows. `workspace.lua` owns the "one project per
  tabpage" model: it is the only place that builds the IDE layout, called both by
  the startup handler in `plugins/explorer.lua` and by the `<leader>tn` picker, so
  a workspace tab and the tab nvim started in are the same thing. The left column
  itself lives in `util/sidebar.lua` for the same reason.
- `lua/plugins/` — one file per plugin, lazy.nvim specs. Three of our own live
  as external plugins under `~/dev` (lazy `dev` path), each declared in a small
  spec here: `fishmonger.lua` (the side terminal, wired into the snacks terminal
  in `terminal.lua`), and `review.lua` (branch review mode = triage.nvim +
  nitpick.nvim, whose neo-tree glyphs are registered in `explorer.lua`).

The side terminal (fishmonger.nvim) runs shells directly in an nvim terminal
buffer. There is no tmux backend; it reimplements tmux's window semantics
(`<C-b>` prefix, hidden-but-alive tabs, `move-window`) natively over snacks, and
draws its tab strip as a window-local winbar on its own side window.

## Conventions

- `stylua` formats Lua on save via conform, configured by `stylua.toml`. Keep
  that file — stylua's *default* is tab indent, and without it a save silently
  reformats a whole file away from the 2-space style used here.
- `.luarc.json` declares the `vim` global and the busted globals. Keep it in
  sync when adding test globals, so lua_ls stays clean outside nvim (CI, a bare
  `lua-language-server`) and not just via the in-editor `lsp.lua` settings.
- Comments explain *why*, and state constraints the code can't. Don't add
  comments describing code that used to be there.

## Keymaps

- **Don't shadow built-in commands.** Keys like `gf`/`gF` (goto file), `gp`/`gP`
  (paste, cursor after), `gy`, `gq`, `gc` mean something in stock Vim; rebinding
  them silently costs a real feature. Prefer an unused key or a `<leader>`
  mapping. If overriding a builtin is genuinely worth it, the mapping should be a
  strict superset of what it replaces, and the trade-off noted in a comment.
- **Make custom commands feel native.** Follow Vim idioms rather than porting
  another editor's model. Prefer register semantics over "the clipboard" (a
  command that reads `v:register`, defaulting to the unnamed register, is more
  Vim-ish — and more general — than one hardcoded to `+`); compose with motions
  and text objects where it fits; mirror the naming and behaviour of the builtin
  a command is analogous to.
- **Only customise what Vim genuinely can't do — don't paper over internals
  worth learning.** A mapping should exist for a real gap (usually layout /
  window routing, which no amount of Vim fluency changes), not to replace a
  native command. Example: `gf`/`gF` differ from the builtins *only* by opening
  in the main window; resolution is still Vim's own (`<cfile>`, `findfile()`,
  `path`/`suffixesadd`). Things with a native answer stay native — fuzzy finding
  is `Ctrl-P`, extracting a path from text is `yi(`/`yiW`.
