# Neovim plugins from nix: design and migration

Every Neovim plugin, the four forks included, comes from nix and is pinned in
this repo's `flake.lock`. The Lua config is built into the same store path, so
**nothing about a machine's nvim changes until `hms`**: not a plugin, not a
config edit pulled from another machine. lazy.nvim stays, but only as the
loader. It never clones, updates or writes.

## Decisions

| Question | Decision |
| --- | --- |
| Wrapper | [nix-wrapper-modules](https://github.com/nix-community/nix-wrapper-modules)' neovim module. nixCats, its predecessor by the same author, is in maintenance mode. |
| Plugin versions | nixpkgs' (the `nixpkgs` input, 26.05), except where a flake input is needed (below). Tests catch regressions. |
| Lua config | Wrapped into the build. `NVIM_CONFIG_DIR` runs another checkout's config on the same plugins, for development. |
| Loader | **lazy.nvim, fed from the store** (see "Why not lze"). |
| Forks | Flake inputs. Each fork repo has its own flake for its test suite. |
| macOS | Kept buildable (`packages.aarch64-darwin.nvim`), verified later. |

### Why not lze

The first draft of this doc proposed rewriting the plugin specs for
[lze](https://github.com/BirdeeHub/lze). Reading the specs changed that.
Eighteen test sites call `require("plugins.x")[1].opts` or `.config()`, and
`config/greeter.lua` waits on lazy's `User VeryLazy`, so the rewrite would mean
2.5k lines of live config plus the tests. lazy.nvim's documented settings for
nix-provided plugins avoid all of that. Every plugin is a "dev" plugin
(`dev.patterns = { "" }`) whose `dev.path` is its store path, and lazy's
rtp/packpath reset is off. Prior art: nixCats' `lazyCat.lua` and the settings its
README lists. Switching to lze later stays possible as a separate refactor.

## Layout

```
flake.nix          inputs (wrappers, forks, other plugin sources); packages.<system>.nvim
nvim-package.nix   the wrapper module: plugins, parsers, config_directory
neovim.nix         unchanged: the neovim-unwrapped build being wrapped
.config/nvim/      the Lua config, copied into the build
  lua/config/lazy.lua         nix branch: lazy loads from the store
  lua/config/plugin_dirs.lua  store path or NVIM_DEV_PLUGINS checkout per plugin
  lua/util/nix_build.lua      the wrapper's info plugin, nil under plain lazy
  lua/util/config_dir.lua     the running config's dir (not stdpath("config"))
```

`nvim-package.nix` puts every plugin in `pack/*/opt` (`lazy = true`), so lazy
alone decides what loads when. Plugin dependencies nixpkgs declares go there too
(`pluginDeps = "lazy"`). The plugins are named as lazy names them; only
`LuaSnip` needs a `pname`. A plugin that's in the Lua specs but missing from
the build stops nvim with "X isn't in the nix build: add it to
nvim-package.nix". It never falls back to a download.

Treesitter: the 24 parsers in `plugins/treesitter.lua` come from
`nvim-treesitter.withPlugins` and land, collated, in `pack/*/start`. Under the
build, `plugins/treesitter.lua` skips `install()`. Parsers left in
`~/.local/share/nvim/site/parser` come later on the runtimepath (checked), so
they're harmless; delete them when convenient.

`settings.config_directory` is
`os.getenv("NVIM_CONFIG_DIR") or "<store copy of .config/nvim>"`.
`stdpath("config")` still names the live `~/.config/nvim`. Code that reads its
own config files (prettierd's defaults, api-linter's config) uses
`util.config_dir`, so the build reads its own copies. The dashboard's
"Config" entry deliberately keeps opening the live checkout, since that's where
edits go.

## Where each plugin comes from

nixpkgs for everything except these flake inputs. Each was first locked to the
commit `lazy-lock.json` runs today, so the switch doesn't change them:

| Input | Why not nixpkgs |
| --- | --- |
| `agentic`, `fishmonger`, `nitpick`, `triage` | Ross's forks / plugins |
| `neo-tree` (`main`) | `tests/neotree_leak_spec.lua` fails on nixpkgs' 3.x (45 live handles vs 31) |
| `render-markdown` | nixpkgs' (2026-05) leaves `breakindentopt` changed once rendering is toggled off (`render_markdown_spec`) |
| `videre`, `graph-view-yaml`, `graph-view-toml` | not in nixpkgs |

**Version drift.** The pinned `nixpkgs` (`1e8bc65`) is older than most of
`lazy-lock.json`, so the switch moves most other plugins *back* by up to eight
months (snacks 2026-05 → 2026-03, nvim-treesitter 2026-10 → 2026-04,
lspconfig → v2.9). The full suite passes on these versions with the inputs
above. Anything the suite doesn't cover will show up in use. The fix is either
another input or `nix flake update nixpkgs`.

## Updating a plugin

A fork (or any input):

1. Commit and push in the fork (the input tracks its `main`).
2. In `~/.dotfiles`: `nix flake update agentic` (or `fishmonger`, `nitpick`,
   `triage`, `neo-tree`, `render-markdown`, ...).
3. `make test` against the new build (below), then commit `flake.lock` alone
   ("nvim: pin agentic's <fix>") and push.
4. `hms` on each machine, then restart nvim.

nixpkgs plugins move with `nix flake update nixpkgs`, which also moves the rest
of the home configuration.

## Developing against the build

Build from a checkout (any worktree) without touching the installed nvim. Keep
the built nvim off Ross's real state:

```sh
nix build ~/.dotfiles#nvim -o /tmp/nvim-dev
x=$(mktemp -d)
XDG_CONFIG_HOME=$x/c XDG_DATA_HOME=$x/d XDG_STATE_HOME=$x/s XDG_CACHE_HOME=$x/k /tmp/nvim-dev/bin/nvim
```

Three escape hatches, from cheapest to most thorough:

| Need | Command | Rebuild |
| --- | --- | --- |
| Try config edits on the pinned plugins | `NVIM_CONFIG_DIR=$PWD/.config/nvim nvim` | none |
| Try a plugin checkout | `NVIM_DEV_PLUGINS=fishmonger.nvim nvim` (`~/dev/fishmonger.nvim`), or `name=dir` for any checkout, comma-separated | none |
| A fork change that needs something new from nix | `nix build ~/.dotfiles#nvim --override-input fishmonger path:$HOME/dev/fishmonger.nvim` | the wrapper |

`NVIM_DEV_PLUGINS` refuses a name the build doesn't carry and a checkout that
isn't there; it never falls back to the pinned copy. `--override-input` with
`path:` includes uncommitted files and never writes `flake.lock`.

Agents verifying a change use the cheapest row that covers it. They run the
nvim they built with scratch XDG dirs, and never `hms`.

**`VIM`/`VIMRUNTIME`.** A terminal inside nvim exports both. Any nvim started
from it that isn't the same build loads the wrong runtime and breaks in odd
ways. The Makefiles here and in the forks unset them. Do the same for one-off
runs (`env -u VIM -u VIMRUNTIME ...`).

## Tests

```sh
cd .config/nvim
make test                                   # whichever nvim is on PATH
make test NVIM_BIN=/tmp/nvim-dev/bin/nvim   # a build
NVIM_DEV_PLUGINS=fishmonger.nvim make test  # against a checkout
```

- `tests/minimal_init.lua` takes the config from its own path, so a worktree
  tests itself. It loads plenary and the plugins specs use through
  `tests/helpers/plugins.lua`, which resolves them as `config/lazy.lua`
  does (store, or `NVIM_DEV_PLUGINS`). Under plain lazy nvim it falls back to
  lazy's install dir.
- PlenaryBustedDirectory runs each spec in a child nvim from `v:progpath`, the
  *unwrapped* binary under nix, so the Makefile passes `nvim_cmd` as the same
  `NVIM_BIN`. The variable isn't `NVIM`: make imports the environment, and
  inside an nvim terminal `$NVIM` is a socket.
- `workspace_tabs_spec` starts the full config in a child: the nvim under test,
  with `NVIM_CONFIG_DIR` set to the checkout being tested.

Forks: `nix develop -c make test` or `nix flake check` in each.
agentic's upstream Makefile reads `NVIM`, so there it's
`nix develop -c make test NVIM=nvim`.

## Migration

Branch `rkk/nix-plugins` (dotfiles) and `rkk/flake` (each fork), not yet on
main. Until the switch, the Lua's nix branch is dead code on the machines, so
merging changes nothing for the running lazy nvim.

1. **Fork flakes** (`rkk/flake` in each fork). Each fork's tests run with
   plenary etc. from its own flake. They still fall back to the lazy install,
   until the cleanup.
2. **Plugin lookup** (`config/plugin_dirs.lua` + spec, `util/nix_build.lua`).
3. **lazy loads from the build when there is one** (`config/lazy.lua`,
   treesitter install, `util/config_dir.lua`).
4. **Tests find plugins wherever the nvim under test does** (helper,
   `minimal_init`, specs, Makefile).
5. **The nix build** (`flake.nix` inputs, `nvim-package.nix`,
   `packages.<system>.nvim`). This is buildable and testable, but no host
   installs it yet.
6. **Switch** (not done): `base.nix` installs `self.packages.<system>.nvim` in
   place of `neovim`, and Ross runs `hms` on each machine. Before then:
   `make test NVIM_BIN=<build>` on the merged main.
7. **Cleanup**, once every machine has switched: drop the lazy-install branch
   of `config/lazy.lua` and `tests/helpers/plugins.lua`, `lazy-lock.json`,
   `tests/lazy_lock_spec.lua`, the forks' lazy-install fallbacks, and
   `~/.local/share/nvim/{lazy,site/parser}`. Update `.config/nvim/CLAUDE.md`'s
   lazy-specific notes.

## Risks and open questions

1. **Drift backwards** (above). The suite passes, but untested behaviour may
   have regressed. Watch the first days after the switch, or bump `nixpkgs` first.
2. **Live scripts vs a pinned config.** `nvim-open`, `worktree-tab` and the
   fish `nvim` function are out-of-store links that call into the running nvim
   (`config.workspace` etc.). After a pull, a script can call a function the
   running build's config doesn't have yet. That's true today too, but now the
   gap lasts until `hms` rather than a restart.
3. **agentic's `should stop at first successful command`** fails on its main
   too, with the current nvim. Its stub never resets `v:shell_error`, so the
   result depends on earlier tests. `nix flake check` there is red until it's
   fixed.
4. **macOS** builds are declared but unverified.
