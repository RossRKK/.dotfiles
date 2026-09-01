return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main", -- the rewrite; setup()/ensure_installed of the master API is gone
    build = ":TSUpdate",
    config = function()
      -- Grouped by language family; stylua would put each on its own line.
      -- stylua: ignore
      local parsers = {
        "lua", "vim", "vimdoc", "query",
        "python", "javascript", "typescript", "tsx",
        "rust",
        "svelte",
        "markdown", "markdown_inline",
        "yaml", "json", "toml",
        "hcl",
        "nix",
        "helm", -- Go-template YAML; injects yaml + gotmpl highlighting
        "bash",
        "html", "css",
        "gdscript", "gdshader", "godot_resource",
      }

      -- Neovim detects .tscn/.tres as filetype "gdresource", but the parser is
      -- named "godot_resource" and nvim-treesitter's main branch registers no
      -- filetype->language mappings. Without this the pcall'd treesitter.start
      -- below silently no-ops on scene and resource files.
      vim.treesitter.language.register("godot_resource", "gdresource")

      -- main-branch install() builds parsers with the upstream `tree-sitter` CLI,
      -- which mason-tool-installer provisions. On a cold machine the CLI often
      -- isn't on PATH yet when this runs, so defer install() until mason signals
      -- it's finished; otherwise build straight away. (install() skips parsers
      -- already present, and highlighting is opt-in per buffer below -- there's no
      -- global `highlight = { enable = true }` on this branch.)
      local function install_parsers()
        require("nvim-treesitter").install(parsers)
      end
      if vim.fn.executable("tree-sitter") == 1 then
        install_parsers()
      else
        vim.api.nvim_create_autocmd("User", {
          pattern = "MasonToolsUpdateCompleted", -- fired by mason-tool-installer
          once = true,
          callback = install_parsers,
        })
      end

      -- Start treesitter highlighting for every buffer whose language has a parser.
      -- pcall keeps it a no-op for filetypes without one, so those fall back to
      -- Neovim's legacy regex syntax highlighting instead of erroring.
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(ev)
          pcall(vim.treesitter.start, ev.buf)
        end,
      })
    end,
  },
  {
    -- Syntax-aware text objects and motions, driven by treesitter queries, so
    -- "a function" means the same thing in every language with a parser.
    "nvim-treesitter/nvim-treesitter-textobjects",
    branch = "main", -- must match nvim-treesitter's branch; the master API is gone
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    event = "VeryLazy",
    config = function()
      require("nvim-treesitter-textobjects").setup({
        select = {
          -- Jump forward to the nearest text object when the cursor isn't inside
          -- one, so `dif` works from the blank line above a function.
          lookahead = true,
        },
        move = { set_jumps = true }, -- the motions below are jumps, so <C-o> comes back
      })

      -- On the main branch there are no default mappings: each one calls the
      -- module directly with a query capture. The captures come from the
      -- textobjects.scm queries bundled with this plugin -- more exist
      -- (@conditional, @loop, @comment, @call); these are the ones worth keys.
      local select = require("nvim-treesitter-textobjects.select")
      local move = require("nvim-treesitter-textobjects.move")
      local swap = require("nvim-treesitter-textobjects.swap")

      -- Text objects. `a` includes the signature/braces, `i` just the body.
      -- ii/ai are snacks' scope objects (see snacks-ui.lua) -- left alone.
      -- stylua: ignore
      local objects = {
        f = "function",
        c = "class",
        a = "parameter",
      }
      for key, capture in pairs(objects) do
        for _, kind in ipairs({ "outer", "inner" }) do
          local lhs = (kind == "outer" and "a" or "i") .. key
          vim.keymap.set({ "x", "o" }, lhs, function()
            select.select_textobject("@" .. capture .. "." .. kind, "textobjects")
          end, { desc = kind .. " " .. capture })
        end
      end

      -- Function motions, on the builtin method-motion keys. These override
      -- ]m/[m (next/prev method start) and ]M/[M (end), and are a strict
      -- superset: the builtins find methods by scanning for `{` at the start of
      -- a line, so they only ever worked in C-like languages and got confused by
      -- braces in strings. The treesitter version is the same motion, correct,
      -- in every language with a parser.
      --
      -- Not ]f/[f, which look free but are deprecated builtin aliases of gf, and
      -- not ]c/[c (gitsigns hunks) or ]a/[a (the arglist commands).
      -- stylua: ignore
      local motions = {
        ["]m"] = { move.goto_next_start,     "Next function" },
        ["[m"] = { move.goto_previous_start, "Prev function" },
        ["]M"] = { move.goto_next_end,       "Next function end" },
        ["[M"] = { move.goto_previous_end,   "Prev function end" },
      }
      for lhs, spec in pairs(motions) do
        local goto_fn, desc = spec[1], spec[2]
        vim.keymap.set({ "n", "x", "o" }, lhs, function()
          goto_fn("@function.outer", "textobjects")
        end, { desc = desc })
      end

      -- Reorder arguments without touching the commas.
      vim.keymap.set("n", "<leader>a", function()
        swap.swap_next("@parameter.inner")
      end, { desc = "Swap parameter with next" })
      vim.keymap.set("n", "<leader>A", function()
        swap.swap_previous("@parameter.inner")
      end, { desc = "Swap parameter with previous" })
    end,
  },
}
