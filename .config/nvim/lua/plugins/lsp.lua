-- On NixOS, Mason can't run the pre-compiled binaries it downloads. Tools and
-- LSP servers are installed via Nix (home-manager) instead, so we skip Mason's
-- ensure_installed / automatic_installation on that platform.
local is_nixos = vim.fn.filereadable("/etc/NIXOS") == 1

return {
  {
    "williamboman/mason.nvim",
    opts = {},
  },
  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = { "williamboman/mason.nvim" },
    opts = {
      ensure_installed = is_nixos and {} or {
        "basedpyright",
        "ts_ls",
        "svelte",
        "lua_ls",
        "yamlls",
        "jsonls",
        "terraformls",
        "marksman",
        "helm_ls",
      },
      automatic_installation = not is_nixos,
      -- automatic_enable vim.lsp.enable()s every mason-installed server, so any
      -- server we don't want started must be listed here even if it's absent from
      -- ensure_installed (dropping it from ensure_installed doesn't uninstall it):
      --   rust_analyzer -- owned/started by rustaceanvim (see rust.lua); without
      --     the exclude a second one attaches, doubling inlay hints (": String: String").
      --   pyright -- leftover mason package from before the basedpyright swap; without
      --     the exclude it attaches alongside basedpyright and doubles gr references.
      automatic_enable = {
        exclude = { "rust_analyzer", "pyright" },
      },
    },
  },
  {
    -- Auto-install CLI tools (not LSP servers) into mason's bin, which mason puts
    -- on nvim's PATH. Here: the tree-sitter CLI that nvim-treesitter's main branch
    -- shells out to for building parsers, so a fresh machine bootstraps itself.
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = { "williamboman/mason.nvim" },
    opts = {
      ensure_installed = is_nixos and {} or {
        "tree-sitter-cli",
        -- Formatters used by conform.lua. rustfmt (rust toolchain) and terraform
        -- (terraform CLI) aren't mason packages, so they're expected on PATH.
        "stylua", -- lua
        "prettierd", -- js/ts/svelte/json/yaml/css/html/markdown
        "ruff", -- python (format + import sort)
        "shfmt", -- sh/bash
        "gdtoolkit", -- gdscript (provides the gdformat bin)
      },
    },
  },
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
      "hrsh7th/cmp-nvim-lsp",
    },
    config = function()
      local capabilities = require("cmp_nvim_lsp").default_capabilities()

      -- Absolute path required: pyright roots at each sub-package's pyproject.toml
      -- (e.g. systems/<name>), so a relative ".venv/bin/python" resolves to a venv
      -- that doesn't exist there and pyright falls back to system Python.
      local venv_python = require("util.venv").python

      -- Configure each server using the new vim.lsp.config API
      local servers = {
        -- basedpyright, not pyright: it's a drop-in fork that additionally serves
        -- inlay hints (return/variable types, call-arg names), which the
        -- LspAttach handler below enables. typeCheckingMode "standard" matches
        -- pyright's default rather than basedpyright's stricter "recommended", so
        -- the switch adds hints without a wall of new diagnostics.
        basedpyright = {
          settings = {
            basedpyright = {
              analysis = { typeCheckingMode = "standard" },
            },
            python = {
              pythonPath = venv_python(),
            },
          },
        },
        ts_ls = {},
        -- rust_analyzer is owned by rustaceanvim (see rust.lua), not started here.
        svelte = {},
        yamlls = {},
        jsonls = {},
        terraformls = {},
        marksman = {},
        -- Helm templates get filetype "helm" (via vim-helm, see helm.lua), so
        -- yamlls skips them and helm_ls handles the Go-template YAML instead.
        -- helm_ls shells out to yaml-language-server (already installed above)
        -- for the embedded YAML, finding it on mason's PATH.
        helm_ls = {},
        -- Not in mason's ensure_installed above: the GDScript server *is* the
        -- Godot editor, which hosts it on 127.0.0.1:6005 (override with
        -- $GDScript_Port). lspconfig's lsp/gdscript.lua supplies the
        -- vim.lsp.rpc.connect cmd and project.godot root marker. Opening a .gd
        -- file with Godot closed logs a connection error and leaves the buffer
        -- on treesitter highlighting alone -- that's expected, not a misconfig.
        gdscript = {},
        lua_ls = {
          settings = {
            Lua = {
              diagnostics = { globals = { "vim" } },
              workspace = { checkThirdParty = false },
            },
          },
        },
      }

      for server, config in pairs(servers) do
        config.capabilities = capabilities
        vim.lsp.config(server, config)
        vim.lsp.enable(server)
      end

      -- Keymaps on LSP attach
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(ev)
          local map = function(keys, func, desc)
            vim.keymap.set("n", keys, func, { buffer = ev.buf, desc = desc })
          end
          -- Nav pickers use snacks (see lua/plugins/picker.lua); each opens a
          -- picker of the candidates, jumping straight through on a single match.
          map("gd", function()
            Snacks.picker.lsp_definitions()
          end, "Go to definition")
          map("gi", function()
            Snacks.picker.lsp_implementations()
          end, "Go to implementation")
          map("gr", function()
            Snacks.picker.lsp_references()
          end, "Go to references")
          map("K", vim.lsp.buf.hover, "Hover docs")
          map("<leader>ca", vim.lsp.buf.code_action, "Code action")
          map("<leader>rn", vim.lsp.buf.rename, "Rename")
          map("<leader>d", vim.diagnostic.open_float, "Show diagnostic")
          map("[d", function()
            vim.diagnostic.jump({ count = -1, float = true })
          end, "Prev diagnostic")
          map("]d", function()
            vim.diagnostic.jump({ count = 1, float = true })
          end, "Next diagnostic")

          local client = vim.lsp.get_client_by_id(ev.data.client_id)
          if client and client:supports_method("textDocument/inlayHint", ev.buf) then
            vim.lsp.inlay_hint.enable(true, { bufnr = ev.buf })
          end

          -- terraformls emits a very large semantic-token batch for files with
          -- deeply nested heredoc/yamlencode blocks (e.g. argocd-bootstrap's
          -- main.tf). Neovim's tokens_to_ranges resolves each token's UTF-16
          -- column with str_utfindex and spins hard enough to freeze the editor
          -- on open. Treesitter already highlights HCL, so drop the capability.
          if client and client.name == "terraformls" then
            client.server_capabilities.semanticTokensProvider = nil
          end
        end,
      })
    end,
  },
}
