return {
  {
    "williamboman/mason.nvim",
    opts = {},
  },
  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = { "williamboman/mason.nvim" },
    opts = {
      ensure_installed = {
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
      automatic_installation = true,
    },
  },
  {
    -- Auto-install CLI tools (not LSP servers) into mason's bin, which mason puts
    -- on nvim's PATH. Here: the tree-sitter CLI that nvim-treesitter's main branch
    -- shells out to for building parsers, so a fresh machine bootstraps itself.
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = { "williamboman/mason.nvim" },
    opts = {
      ensure_installed = {
        "tree-sitter-cli",
        -- Formatters used by conform.lua. rustfmt (rust toolchain) and terraform
        -- (terraform CLI) aren't mason packages, so they're expected on PATH.
        "stylua", -- lua
        "prettierd", -- js/ts/svelte/json/yaml/css/html/markdown
        "ruff", -- python (format + import sort)
        "shfmt", -- sh/bash
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
          local builtin = require("telescope.builtin")
          map("gd", builtin.lsp_definitions, "Go to definition")
          map("gi", builtin.lsp_implementations, "Go to implementation")
          map("gr", builtin.lsp_references, "Go to references")
          map("K", vim.lsp.buf.hover, "Hover docs")
          map("<leader>ca", vim.lsp.buf.code_action, "Code action")
          map("<leader>rn", vim.lsp.buf.rename, "Rename")
          map("<leader>d", vim.diagnostic.open_float, "Show diagnostic")
          map("[d", vim.diagnostic.goto_prev, "Prev diagnostic")
          map("]d", vim.diagnostic.goto_next, "Next diagnostic")

          local client = vim.lsp.get_client_by_id(ev.data.client_id)
          if client and client.supports_method("textDocument/inlayHint") then
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
