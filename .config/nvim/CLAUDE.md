# Neovim config

Personal Neovim config, tracked in the dotfiles repo, whose root is two levels
up from here; home-manager symlinks this directory into `$HOME`. The workflow
is documented in `../../README.md`.

User-facing keymaps and features are documented in `../../cheatsheet.md` (a broader
sheet also covering tmux and the dotfiles commands). **Keep it in sync:** when
you add, remove, or rebind a mapping here, update the matching table there.

## Tests

There is a test suite. **Run it after changing anything under `lua/`:**

```bash
cd ~/.config/nvim && make test
```

It runs headless via plenary's busted harness and exits non-zero on failure.
A single file: `make test FILE=tests/ide_spec.lua`. Against a nix build of
nvim: `make test NVIM_BIN=<build>/bin/nvim`; against a plugin checkout:
`NVIM_DEV_PLUGINS=fishmonger.nvim make test` (see `../../docs/nvim-nix-migration.md`).

Specs live in `tests/*_spec.lua` and cover the pure logic worth pinning:

| Spec             | Covers                                    |
| ---------------- | ----------------------------------------- |
| `ide_spec.lua`      | side-terminal width, explorer geometry |
| `worktree_spec.lua` | worktree dir naming, `<M-b>w` rows carry (and match) the agent whose worktree has the branch, its name in its colour (running claim, else its latest transcript's last `agent-color` row; dimmed when unknown), a detached worktree is a row by its sha that opens it as it is (temp repo), every kind of row draws through snacks' real `git_branch` formatter with its commit subject (temp repo, loads real snacks), `git worktree add` flags, git progress-line parsing; agent worktrees: naming, and a new one for any branch not checked out, on a temp repo; `<leader>tX` removal on a temp repo: jobs stopped (a running agent never asked about) and files and terminals wiped before the tab closes, plugin scratch buffers left to it (loads real neo-tree: its hijack guard never deletes the landed tab's buffer), `--force` only once a dirty checkout is confirmed |
| `claude_session_spec.lua` | a live Claude's name from Claude Code's `sessions/<pid>.json`; none for a missing, half-written or unnamed record; a checkout's standing role from `claude-roles` (`~` expanded) |
| `workspace_state_spec.lua` | saved workspaces: two nvims' saves merge per project, a deliberate close drops one but exit doesn't, an absent agent keeps its last session id; restore skips and forgets a deleted directory, resumes only a session with a transcript |
| `term_caps_spec.lua` | inline-image capability (Ghostty yes, Neovide/other no) |
| `clipboard_spec.lua` | text-vs-image clipboard sniffing for paste; the clipboard's text read without raising when Neovide's provider fails on an image; the image or copied files read from Windows on WSL, the macOS pasteboard on a Mac, Wayland under `$WAYLAND_DISPLAY`, else a notify and no spawn (X11): an image or Explorer- or Finder-copied files from the PowerShell or JXA script's `png`/`file` lines, the type taken from `wl-paste --list-types` (PNG, else `text/uri-list`) and its content as an image or local paths; a copied path, Linux or quoted Windows (real `wslpath`); the Neovide provider reads a clipboard Neovide can't (an image) as empty |
| `reviewqueue_spec.lua` | CODEOWNERS glob matching / last-match-wins, "does this PR need my review" tiers, "what's my PR waiting on" tiers |
| `gh_header_spec.lua` | the real snacks' gh:// buffer header as reshaped: Repo and Changes gone, opened and updated on one line in snacks' relative time, mergeable and merge status on one line (either alone, neither none), in snacks' order; a prop gone after a snacks bump is an error |
| `diffsize_spec.lua` | PR diff size by review tier: path rules, `git check-attr` parsing and overrides, headline sums without generated, bar widths and colours, grouping files by tier; the PR body section (files by tier, binary marked) and replacing it in a body (present, absent, unclosed) |
| `background_spec.lua` | side-terminal shells wrapped into systemd's `background.slice` only when a user manager is running |
| `sidebar_reveal_spec.lua` | `<leader>v` reveals in the tree without re-rooting it or `:tcd`-ing the tab; files outside the workspace float at their project root. Loads real neo-tree |
| `sidebar_refresh_spec.lua` | the docked tree shows a file created outside nvim (libuv watcher), and re-reads on entering its tab: a refresh issued while the tab was in the background, or one whose render neo-tree dropped because the tab was left mid-refresh. Runs the real `plugins/explorer.lua` config() against the installed neo-tree |
| `workspace_tabs_spec.lua` | workspace tabs opened from the start screen, restored (`s`, `:WorkspaceRestore`) or opened in one burst each get the hand-opened layout (winlayout + filetypes) and one statusline at the screen bottom; `s` resumes every saved session, however it was saved, as an agent chat; a file opened from neo-tree after visiting the todo split replaces the greeter and the split. Ctrl+B Z with an agent chat puts the todo split away with the prompt still at its opening height, and a file then opened beside the chat gets a fair share of the editor area. An agent chat in the side panel opens at the panel's width with its prompt at agentic's 10 rows; Ctrl+B Z takes it to the editor area and back even when its prompt is wider than the editor, from its prompt, and from a zoom; unzooming on a resized screen lays it out for that screen. The chat, its prompt, a Ctrl+B f list and a Ctrl+B " pane stay in the panel's column, which follows screen resizes; Ctrl+Right in the chat widens it and Space+wr puts it back, Ctrl+Up in the prompt heightens it. Drives a child nvim with the full config on a pty, terminal 1 running sh |
| `buffers_spec.lua` | the current buffer stays on the bar beside the workspace tabs: their labels shorten a step at a time (repo, then branch) only once strip and tile no longer fit. Loads real bufferline |
| `api_linter_spec.lua` | api-linter JSON to diagnostics; proto root (buf module, else git checkout, else the file's dir); the real api-linter (on PATH, common protos linked by home-manager) flags a camelCase field, resolves `google/api` imports, ignores a repo's opt-outs, skips the Java-option rules |
| `agentic_spec.lua` | the agent chat's buffers, built by the installed agentic.nvim under this config's opts, leave `q` unbound; its windows, a fishmonger host included, draw no wrap marker, and the host's other buffers keep the global one; a thinking block written by agentic's real writer parses as no blockquote |
| `render_markdown_spec.lua` | a table rendered in an agent chat by the real render-markdown under this config's tokyonight: borders in the comment grey, the header bold in the normal foreground, body cells uncoloured; a write to the concealed chat leaves its treesitter parse to the next redraw (no conceal_lines left in the markdown query); headings and bullets keep their `###` and `-` markers, no icon or sign drawn over them; on screen, a wrapped quote keeps its bar and a wrapped list item (in a quote too) hangs under its text, in a chat (no wrap marker) and a markdown file (the marker hung, hidden under the bar), and toggling rendering off restores the window's `breakindentopt`; HTML lists draw as markdown's `- ` items, their tags hidden, and a `<summary>` is marked |
| `agent_close_spec.lua` | closing a tab with an agent chat ends its agentic session, an update the agent already sent dropped without an error. The full config in a child nvim against `tests/helpers/fake_acp_agent.py`, an agent that only opens a session |
| `agent_chat_spec.lua` | `<leader>ya`'s `fishmonger.send` types into an agent chat's prompt, not its chat; Ctrl+V in an agent chat's prompt: a copied image is attached as a PNG of it, copied files and a copied path to a file are attached, other text is typed, an empty clipboard says so; p/P attach the same, otherwise put text natively with a count, and another register puts that register |
| `markdown_links_spec.lua` | the URL of the markdown link under the cursor, for `gd` to open: an inline link (any scheme, `<...>` unwrapped), an autolink, a reference link through its definition, in markdown and agent chats; none for a relative file, an anchor, file+anchor, off a link, or a buffer without a parser |
| `hardtime_spec.lua` | on the real hardtime under this config: insert-mode `<Up>`/`<Down>` move through an open builtin completion menu (agentic's prompt), stay disabled without one, and both still hold after a toggle off and on |
| `options_spec.lua` | the mouse starts off (`<leader>um` turns it on) |
| `message_log_spec.lua` | each nvim's messages (multi-line text intact) go via 'verbosefile' to its own log named by start time and pid; only the newest previous logs are kept, other files in the log dir untouched |
| `quickfix_spec.lua` | a set quickfix list becomes current and docks under the main window without taking focus, one window for the next list; its state names the current entry and the entries the cursor has been on (a moved line followed, a line without an entry not counted), none for an empty list; `]q` from a window that is not an editor lands in the main window, `]Q` with no count goes to the last entry |
| `todo_spec.lua` | the todo toggle opens below the main window (else the current non-panel window) and focuses it; the split closes for anything but the greeter put in the window it sits under (a file, a terminal, an unlisted or scratch buffer, from any window), not for the greeter's return, a buffer in another window, or a float; a file opened in the split itself (`:e`, a set buffer) moves to the greeter's window and the split closes, reloading the list doesn't |
| `windows_spec.lua` | main-window routing: a file window first, else a terminal in the main area (never the side panel or a float); `open` lands a file there at a line and column, a line past the end clamped; a placeholder holds its window's height only beside a companion, and lets go once a file is shown there |
| `neotree_leak_spec.lua` | the pinned neo-tree doesn't leak timers/process handles across renders. Loads the real plugin (and its git status): it guards the pin, not our code. `NVIM_DEV_PLUGINS=neo-tree.nvim=<checkout>` tests another build |
| `plugin_dirs_spec.lua` | under the nix build, each plugin loads from its dir in the build, or from a checkout `NVIM_DEV_PLUGINS` names (`name` under `~/dev`, or `name=dir`, linked under the plugin's name when its directory has another); a missing checkout, a name the build lacks and a plugin the build lacks are errors, never a fallback |
| `nix_build_spec.lua` | the nix build is read from the wrapper's info plugin (plugin dirs, config dir, nvim), and is absent in any other nvim |
| `lua_path_spec.lua` | the nvim under test keeps Lua's default search paths (`./?.lua`, `./?.so`) with `LUA_PATH`/`LUA_CPATH` unset |
| `plugin_loading_spec.lua` | the full config, in the nvim under test: lazy can tell every plugin by its directory's name, so a `require()`d plugin loads with its spec's opts (agentic's, checked); render-markdown attaches to snacks' `markdown.gh` buffers, so a gh PR's comments below the first screen render |

The side-terminal and branch-review logic now live in external plugins, each
with its own test suite and flake (`nix develop -c make test`), developed
under `~/dev` and loaded from there with `NVIM_DEV_PLUGINS`:
[fishmonger.nvim](https://github.com/RossRKK/fishmonger.nvim) (the side terminal),
[triage.nvim](https://github.com/RossRKK/triage.nvim) (per-file review status +
verdict rollup),
and [nitpick.nvim](https://github.com/RossRKK/nitpick.nvim) (inline GitHub comments).

`tests/minimal_init.lua` loads this checkout's config plus plenary (and puts
fishmonger's modules on the runtimepath, for its real glyph widths), and
deliberately does **not** load lazy.nvim — no plugin `config()` runs. A spec
that needs a plugin object fakes it (keeping the real arity of any stubbed
`vim.*` function); one that runs a real plugin puts it on the runtimepath with
`require("tests.helpers.plugins").add(name)`, which finds it where the nvim
under test does.

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
  itself lives in `util/sidebar.lua` for the same reason. `util/worktree.lua` is
  the git side of the same idea: it turns a branch into a worktree under
  `<repo>/.worktrees/` and hands the directory to `workspace.open`.
- `lua/plugins/` — one file per plugin, lazy.nvim specs. Every plugin comes
  from the nix build (`../../nvim-package.nix`; add a new plugin there too).
  Three of our own live as external plugins under `~/dev`, each declared in a small
  spec here: `fishmonger.lua` (the side terminal, set up in that spec's
  `config`), and `review.lua` (branch review mode = triage.nvim +
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
  in the main window; resolution is the builtin itself (`<C-w>f`/`<C-w>F`
  into a split that's folded into the main window). Things with a native answer
  stay native — fuzzy finding is `Ctrl-P`, extracting a path from text is
  `yi(`/`yiW`.
