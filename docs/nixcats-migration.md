# Neovim plugins from nix (nixCats): design and migration

Status: proposal, not implemented. Written 2026-11-23 against nixpkgs `ea9e3ef`
(the `nixos-26.05` pin in `flake.lock`) and nixCats-nvim `8fcebab`.

Goal: every Neovim plugin, the four forks included, comes from nix and is
pinned in this repo's `flake.lock`. A machine's plugins change only on
`nix flake update` + `hms`. lazy.nvim stops being a package manager.

Two things to read before the rest:

- **nixCats is in maintenance mode.** Its README now sends new users to
  [nix-wrapper-modules](https://github.com/nix-community/nix-wrapper-modules)
  (same author, same "install with nix, configure with Lua" model, same lze
  recommendation). The core keeps working and fixes get mirrored, but templates
  may be deleted. Everything below except the Nix in section 1 is
  framework-neutral (lze, flake inputs, the dev override, the test harness), so
  the switch costs only that one file. See open question 1.
- **Verified in a spike** (scratchpad flake: nixCats + lze + fishmonger as a
  flake input): the pinned load, the `--override-input` rebuild, the runtime
  `~/dev` override through lze's `load` hook, the `wrapRc` env-var unwrap, and
  `-u tests/minimal_init.lua` reaching nix plugins through `packadd`. The neo-tree
  leak spec was also run against nixpkgs' neo-tree (it fails, see section 2).
  Nothing else here has been run.

## 1. Target layout

```
flake.nix            inputs: nixCats, the 4 forks, plugins nixpkgs lacks or lags
                     outputs: packages.<system>.nvim (nixCats baseBuilder)
nvim-package.nix     categoryDefinitions + packageDefinitions (plugins, runtime deps)
neovim.nix           unchanged: the neovim-unwrapped build the package wraps
base.nix             home.packages: `neovim` -> the flake's `nvim` package
.config/nvim/        Lua config, still symlinked to ~/.config/nvim (unwrapped)
```

**Use `utils.baseBuilder`, not nixCats' home-manager module.** The builder
takes the flake's existing `pkgs` (`baseBuilder luaPath { pkgs = pkgsLinux
system; } categoryDefinitions packageDefinitions "nvim"`), so the `neovim.nix`
overlay and the unstable overrides apply unchanged. It also gives a real
`packages.<system>.nvim` output, which `nix build`/`nix run --override-input`
need (section 5). base.nix keeps nvim as a plain package, as it does today. The
HM module would hide the package under `homeConfigurations.<host>.config.nixCats.out`
and add nothing here.

**Keep the Lua config unwrapped (`wrapRc = false`), read from `~/.config/nvim`.**

- Config edits still take effect on restart, with no `hms` and no `git add`
  (flakes only see tracked files). Ross gave up the fast loop for *plugins*, not
  for his own config.
- The test suite, `nvim-open`, `worktree-tab` and the child-nvim specs all
  assume the config is a live directory, and stay as they are.
- What's lost: `nix run github:RossRKK/dotfiles#nvim` on a machine without the
  checkout. Nobody does that today.
- A config change that needs a new plugin needs an `hms` before it works.
  That's inherent and the same as any nix-installed dependency.

`wrapRc` can also be set to an env var name (verified: with
`wrapRc = "NVIM_UNWRAP"`, setting `NVIM_UNWRAP=1` switches a wrapped build to
`unwrappedCfgPath`). That's only worth having if Ross later wants a wrapped
default. Not recommended now.

Runtime deps: the LSP servers, formatters, `tree-sitter`, `imagemagick`, debug
adapters and `claude-agent-acp` stay in `home.packages`, so terminals and
agents keep them too. Moving the nvim-only ones into `lspsAndRuntimeDeps`
(suffixed onto nvim's PATH) is possible later but out of scope.

## 2. Plugin inventory

All from `pkgs.vimPlugins` (26.05) unless marked. "Drift" means nixpkgs'
revision differs from today's `lazy-lock.json`, so the switch changes that
plugin's version.

| lazy name | nix source | notes |
| --- | --- | --- |
| RossRKK/agentic.nvim | input `agentic` | fork; `branch = main` |
| RossRKK/fishmonger.nvim | input `fishmonger` | fork |
| RossRKK/nitpick.nvim | input `nitpick` | fork |
| RossRKK/triage.nvim | input `triage` | fork |
| nvim-neo-tree/neo-tree.nvim | input `neo-tree` (`github:nvim-neo-tree/neo-tree.nvim/main`) | **must stay an input**: `NEOTREE_PATH=<nixpkgs 3.42.0> make test FILE=tests/neotree_leak_spec.lua` fails (45 handles vs 31) |
| Owen-Dechow/videre.nvim | input `videre` | not in nixpkgs |
| Owen-Dechow/graph_view_yaml_parser | input `graph-view-yaml` | not in nixpkgs |
| Owen-Dechow/graph_view_toml_parser | input `graph-view-toml` | not in nixpkgs |
| folke/lazy.nvim | dropped | |
| (new) lze, lzextras | `lze`, `lzextras` | the only startup plugins |
| L3MON4D3/LuaSnip | `luasnip` | drift (v2.5.0); pack dir is `luasnip`, the one name that differs from lazy's |
| hrsh7th/nvim-cmp, cmp-buffer, cmp-nvim-lsp, cmp-path, saadparwaiz1/cmp_luasnip | same names | sources register from `after/plugin`: load with `lzextras.loaders.with_after` |
| 3rd/image.nvim | `image-nvim` | drift (v1.5.1); nixpkgs builds the `magick` rock itself, so the `rocks = { enabled = false }` workaround goes |
| nvim-treesitter/nvim-treesitter | `nvim-treesitter` | nixpkgs' is the `main` rewrite (has `install.lua`); drift; parsers below |
| nvim-treesitter-textobjects | `nvim-treesitter-textobjects` | same commit |
| akinsho/bufferline.nvim | `bufferline-nvim` | drift (v4.9.1) |
| bngarren/checkmate.nvim | `checkmate-nvim` | drift (v0.12.1) |
| stevearc/conform.nvim | `conform-nvim` | same |
| folke/edgy.nvim | `edgy-nvim` | same |
| folke/flash.nvim | `flash-nvim` | same |
| akinsho/git-conflict.nvim | `git-conflict-nvim` | drift (v2.1.0) |
| lewis6991/gitsigns.nvim | `gitsigns-nvim` | drift (2.1.0) |
| m4xshen/hardtime.nvim | `hardtime-nvim` | drift (v1.3.0); `hardtime_spec` covers our use |
| smjonas/inc-rename.nvim | `inc-rename-nvim` | same |
| lukas-reineke/indent-blankline.nvim | `indent-blankline-nvim` | drift (v3.10.1) |
| nvim-lualine/lualine.nvim | `lualine-nvim` | same |
| nvim-neotest/neotest, nvim-nio, antoinemadec/FixCursorHold.nvim | `neotest`, `nvim-nio`, `FixCursorHold-nvim` | neotest, nio drift |
| MunifTanjim/nui.nvim | `nui-nvim` | drift (0.4.0) |
| windwp/nvim-autopairs | `nvim-autopairs` | same |
| mfussenegger/nvim-dap, rcarriga/nvim-dap-ui | `nvim-dap`, `nvim-dap-ui` | same |
| chrisgrieser/nvim-early-retirement | `nvim-early-retirement` | same |
| mfussenegger/nvim-lint | `nvim-lint` | drift |
| neovim/nvim-lspconfig | `nvim-lspconfig` | drift (v2.12.0) |
| kylechui/nvim-surround | `nvim-surround` | drift |
| nvim-tree/nvim-web-devicons | `nvim-web-devicons` | drift (v0.100) |
| nvim-lua/plenary.nvim | `plenary-nvim` | same |
| MeanderingProgrammer/render-markdown.nvim | `render-markdown-nvim` | drift (v8.14.0); `render_markdown_spec` pins behaviour we rely on |
| mrcjkb/rustaceanvim | `rustaceanvim` | drift (v9.2.1) |
| folke/snacks.nvim | `snacks-nvim` | same; specs split over 5 files, see section 3 |
| folke/todo-comments.nvim | `todo-comments-nvim` | drift (v1.5.0) |
| folke/tokyonight.nvim, trouble.nvim, which-key.nvim | `tokyonight-nvim`, `trouble-nvim`, `which-key-nvim` | same |
| mbbill/undotree | `undotree` | same |
| towolf/vim-helm | `vim-helm` | same |

For drifted plugins, take the nixpkgs version and let the suite (step 5) plus a
day of use be the check. Promote one to a flake input only when a spec or real
use shows the drift matters, as neo-tree's already does. The alternative is to
make every plugin an input pinned to its lazy-lock commit. That means no
behaviour change at the switch, but ~50 inputs, and you own every build quirk
nixpkgs patches today (require checks, the image.nvim rock).

Forks and other inputs are built with
`pkgs.vimUtils.buildVimPlugin { pname = "agentic.nvim"; version =
inputs.agentic.shortRev or "dirty"; src = inputs.agentic; }`. nixpkgs runs a
require check over every module by default. Plugins whose modules need
another plugin at require time (nitpick and triage want neo-tree, for example)
need `dependencies` or `nvimSkipModules`. `pname` must equal the name lze
loads.

**Build steps.** The only lazy `build` hook is treesitter's `:TSUpdate`, which
goes away (below). No plugin needs luarocks from us any more: image.nvim's rock
comes built from nixpkgs.

**Treesitter parsers.** Put
`nvim-treesitter.withPlugins (p: with p; [ lua vim vimdoc query python ... ])`
in startupPlugins, with the 24 languages `plugins/treesitter.lua` lists today.
All 24 exist in nixpkgs, `gdscript`, `gdshader`, `godot_resource` and `helm`
included. Delete the `install()` call, the `MasonToolsUpdateCompleted` wait and
the `tree-sitter`/`gcc` packages' "compile parsers" job. Keep the `FileType` →
`vim.treesitter.start` autocmd and the `gdresource` registration. The parsers
bundled in `neovim.nix`'s build stay as they are. Delete the parsers left in
`~/.local/share/nvim/site/parser/` after the switch: they come earlier on rtp and
would shadow the nix ones.

**Mason.** Already gone: `lsp.lua` and `dap.lua` say so and base.nix installs
the servers. Two comments still claim mason. `rust.lua` says codelldb is
"installed via mason" (it comes from base.nix), and `treesitter.lua` waits on a
mason event that never fires. Both go in step 4.

## 3. Lazy-loading: lze, not lazy.nvim

Recommendation: [lze](https://github.com/BirdeeHub/lze) plus
[lzextras](https://github.com/BirdeeHub/lzextras).

- lazy.nvim is a package manager that resets `rtp`/`packpath` and only loads
  what its own specs name. Under nix it needs `dev.path` functions,
  `dev.patterns = { "" }`, `performance.rtp.reset = false`,
  `performance.reset_packpath = false` and name agreement for every plugin.
  nixCats' author, whose `lazyCat.lua` wrapper exists for this, now calls that
  path "not the best way" and points to lze or lz.n.
- lze only decides *when* to `packadd`. Its `vim.g.lze.load` hook is the single
  place where the `~/dev` override goes (section 5); this was verified in the spike.
- lze over [lz.n](https://github.com/lumen-oss/lz.n): both fit. lze comes from
  the nixCats author and is what nixCats' templates use. lzextras adds what this
  config needs: `merge` (snacks.nvim's opts and keys spread over `dashboard`,
  `git`, `picker`, `snacks-ui` and `terminal`, which lazy merges for us and lze
  does not), `with_after` (cmp sources), `mod_dir_to_spec("plugins")` (keeps
  one file per plugin) and an `lsp` handler.

Spec translation, file by file:

| lazy | lze |
| --- | --- |
| `"owner/repo"` | `"repo-name"` (the pack dir name) |
| `opts = {...}` | `after = function() require(mod).setup({...}) end` |
| `config = fn` | `after = fn` |
| `init = fn` | `beforeAll` / `before` |
| `event`, `ft`, `cmd`, `keys` | same names; `VeryLazy` → `DeferredUIEnter` |
| `lazy = false` | `lazy = false` |
| `dependencies = { x }` | `x` gets `dep_of = { this }`, or `on_require` |
| `cond = fn` | `enabled = fn` (image.nvim's term_caps check) |
| `branch`, `version`, `dev`, `build` | gone (nix's job) |

`plugins/open-external.lua` returns an empty spec and runs at import time. Move
it to `lua/config/` and require it from `init.lua`.

## 4. Forks and plugin inputs

```nix
inputs = {
  nixCats.url = "github:BirdeeHub/nixCats-nvim";
  agentic    = { url = "github:RossRKK/agentic.nvim/main"; flake = false; };
  fishmonger = { url = "github:RossRKK/fishmonger.nvim";   flake = false; };
  nitpick    = { url = "github:RossRKK/nitpick.nvim";      flake = false; };
  triage     = { url = "github:RossRKK/triage.nvim";       flake = false; };
  neo-tree   = { url = "github:nvim-neo-tree/neo-tree.nvim/main"; flake = false; };
  videre = ...; graph-view-yaml = ...; graph-view-toml = ...;
};
```

The input name is the `nix flake update` argument. Updating a machine to a fork
change:

1. In `~/dev/<repo>`: commit and push to the branch the input tracks (`main`).
2. In `~/.dotfiles`: `git pull --rebase`, then `nix flake update agentic` (or
   `fishmonger`, `nitpick`, `triage`; several at once is fine).
3. `hms`, then restart nvim. Run `make test` (section 6) before committing.
4. Commit `flake.lock` alone ("nvim: pin agentic's <fix>", as the lazy-lock
   commits read today) and push.
5. Other machines: `git pull` + `hms`.

`lazy-lock.json` and `tests/lazy_lock_spec.lua` exist to keep `~/dev` plugins
pinned. `flake.lock` does that now, so they're deleted at the switch.

## 5. Dev workflow against `~/dev` checkouts

Two mechanisms, both verified in the spike.

**Runtime override (the default; no rebuild).** One env var, read once in
`init.lua` and passed to the loader:

```sh
NVIM_DEV_PLUGINS=agentic.nvim,fishmonger.nvim nvim            # throwaway full nvim
NVIM_DEV_PLUGINS=fishmonger.nvim nvim --headless -c '...' +qa  # agent check
```

The loader (`lua/util/plugin_loader.lua`, say) is lze's `vim.g.lze.load`. For a
name in the list whose `~/dev/<name>` exists, it prepends that directory to rtp
and sources its `plugin/**` and `ftdetect/**` (rtp-prepend skips what `packadd`
would run; no fork has these today, but a checkout may add them). Otherwise it
calls `lzextras.loaders.with_after(name)`. This only works because every plugin
is `opt` and goes through lze. A `start` plugin is on rtp before `init.lua`
runs.

Dead end, for the record: putting a `pack/dev/opt/<name>` symlink first on
`packpath` does not work. `packadd` adds every match and the nix copy still
comes first on rtp.

What it can't do is change nix-side inputs. If the fork's branch needs a new
plugin, rock or binary, use:

**Rebuild with an overridden input.**

```sh
nix run ~/.dotfiles#nvim --override-input fishmonger path:$HOME/dev/fishmonger.nvim -- --headless ...
nix build ~/.dotfiles#nvim --override-input agentic path:$HOME/dev/agentic.nvim -o /tmp/nvim-dev && /tmp/nvim-dev/bin/nvim
```

`path:` includes uncommitted and untracked files, which is right for an agent
verifying work in progress. `git+file://` builds only the checkout's `HEAD`. The
override does not write `flake.lock` (checked byte for byte). Each run copies the
checkout into the store, a few seconds.

Agents should use the runtime override for tests and quick checks, and
`--override-input` only when the change touches nix. Neither touches
`flake.lock` or the running editor.

**Gotcha:** a shell inside nvim inherits `VIM` and `VIMRUNTIME` from the parent.
If the child is a different nvim build (`--override-input` builds after a
nixpkgs bump, or any nvim after `hms` from a terminal opened before it), it
loads the parent's runtime and breaks. In the spike that meant
`vim._watch`/`nvim_on` errors. Prefix dev runs with `env -u VIM -u VIMRUNTIME`,
or have the loader-side scripts do it.

## 6. Test harness

- `tests/minimal_init.lua`: replace the `stdpath("data")/lazy/plenary.nvim` check
  with `vim.cmd.packadd("plenary.nvim")`. Verified: under the nixCats wrapper,
  `-u tests/minimal_init.lua` skips the config (VIMINIT is ignored) but the
  wrapper's `--cmd` still puts the nix pack dir on `packpath`. Load fishmonger
  through the same loader as section 5, so `NVIM_DEV_PLUGINS` works in tests
  too. Take the config root from the init file's own path
  (`<sfile>:p:h:h`, as the forks do) rather than `~/.config/nvim`, so a
  worktree's `make test` tests that worktree.
- Specs that prepend `stdpath("data") .. "/lazy/<name>"` (buffers, worktree,
  sidebar_reveal, sidebar_refresh, neotree_leak, render_markdown, hardtime,
  agent_chat, agentic, review_base_test) switch to one helper,
  `tests/helpers/plugins.lua`: `load(name)` goes through the loader.
  `NEOTREE_PATH` becomes `NVIM_DEV_PLUGINS`.
- `workspace_tabs_spec` starts `nvim` from PATH with the full config. It then
  gets the nix nvim with no change, and should also unset `VIM`/`VIMRUNTIME`
  for the child.
- Command, unchanged: `cd ~/.config/nvim && make test`. Against a checkout:
  `NVIM_DEV_PLUGINS=fishmonger.nvim make test`.
- Fork repos: fishmonger, nitpick and triage `minimal_init.lua` read plenary
  from the lazy dir too. Change them to `packadd plenary.nvim` (run with Ross's
  nvim), or give each a small flake (open question 4). agentic's suite clones
  mini.nvim itself and needs nothing.

## 7. Migration steps

Each step is one or more commits on main, and nvim keeps working after each.

1. **lze under lazy.** Add lze and lzextras as lazy plugins. Rewrite
   `lua/plugins/*.lua` as lze specs, a few files per commit, with lazy reduced to
   a downloader: one `lua/config/lazy.lua` list of `{ url, name, lazy = true }`
   (names matching nix pack dirs, e.g. `name = "luasnip"`), with lze's `load`
   calling `require("lazy").load({ plugins = { name } })`. Each commit runs
   `make test`. *Still on lazy; behaviour unchanged.*
2. **Build the nix package beside it.** Add the `nixCats` and plugin inputs,
   `nvim-package.nix` and `packages.<system>.nvim`, installed by base.nix as
   `nvim-nix` (alias; `configDirName = "nvim"` so state is shared). `init.lua`
   picks the loader by whether nixCats is present (`require("nixCats")` is
   pcall-able). Treesitter install moves behind the same check. *Daily nvim is
   still lazy; `nvim-nix` is the nix one to try.* Check `nix build .#nvim` on
   aarch64-darwin (aether) here.
3. **Dev loader + harness.** `NVIM_DEV_PLUGINS` loader, `tests/helpers/plugins.lua`,
   and the `minimal_init` changes. Run the suite under both nvims.
4. **Switch.** base.nix installs the nix package as `nvim`. Delete
   `config/lazy.lua`, the loader branch, `lazy-lock.json`, `lazy_lock_spec`,
   the treesitter `install()` code and the stale mason comments. Update
   `.config/nvim/CLAUDE.md` (the `dev` path paragraphs, the spec table), the
   README and the cheatsheet if any command changed. `hms` on all four hosts.
5. **Drift check.** `make test`, and read the drifted plugins' changelogs
   (section 2). Pin by input any that regressed.
6. **Clean up machines.** `rm -rf ~/.local/share/nvim/lazy
   ~/.local/share/nvim/site/parser` on each host (after step 4; the fork suites
   need their plenary change first).
7. **Fork repos.** Change the plenary path in fishmonger, nitpick and triage
   `minimal_init.lua`, then commit and push each.

## 8. Risks and open questions

1. **nixCats or nix-wrapper-modules?** nixCats is maintenance-only and its
   author recommends nix-wrapper-modules' neovim module. That module takes plugin
   *specs* that may be out-of-store paths, which could replace the
   `NVIM_DEV_PLUGINS` loader with a second `nvim-dev` package built from
   `~/dev` paths. Sections 2–7 carry over unchanged. Lean: build on
   nix-wrapper-modules unless Ross wants nixCats specifically. Decide before
   step 2.
2. **Drift at the switch.** About 20 plugins move to nixpkgs' revisions in one
   go. render-markdown and hardtime have specs pinning behaviour, the rest only
   daily use. Accept that, or pin all to lazy-lock commits for the switch?
3. **Plugin update cadence** now follows nixpkgs (26.05 stable). Getting a newer
   upstream plugin means an input or an unstable overlay entry, as `flake.nix`
   already does for atmos and openspec.
4. **Fork test suites** depend on Ross's nvim for plenary. Fine for now; a
   per-fork `flake.nix` with `checks` would make them standalone.
5. **Lua config vs plugin set drift.** Config is live (unwrapped) but plugins
   change on `hms`, so a config commit that relies on a new plugin breaks until
   the next switch. Same as today with a missing `:Lazy sync`, now explicit.
6. **Mac and WSL.** All of this is pure Lua plus nixpkgs builds, so nothing
   platform-specific was found, but only x86_64-linux was built. Build on aether
   in step 2.
7. **`VIM`/`VIMRUNTIME` leaking** into nvims started from nvim terminals
   (section 5). It predates this work, but nix-built variants hit it more often.
   Worth a fix in fishmonger's shell env.
