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
        "pyright",
        "ts_ls",
        "rust_analyzer",
        "svelte",
        "lua_ls",
        "yamlls",
        "jsonls",
        "terraformls",
        "marksman",
      },
      automatic_installation = true,
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

      -- Find the uv .venv interpreter by walking up from the cwd. Absolute path
      -- is required: pyright roots at each sub-package's pyproject.toml (e.g.
      -- systems/<name>), so a relative ".venv/bin/python" resolves to a venv
      -- that doesn't exist there and pyright falls back to system Python.
      local function venv_python()
        local venv = vim.fs.find(".venv", {
          upward = true,
          path = vim.fn.getcwd(),
          type = "directory",
          limit = 1,
        })[1]
        if venv then
          local py = venv .. "/bin/python"
          if vim.fn.executable(py) == 1 then
            return py
          end
        end
        return nil
      end

      -- Configure each server using the new vim.lsp.config API
      local servers = {
        pyright = {
          settings = {
            python = {
              pythonPath = venv_python(),
            },
          },
        },
        ts_ls = {},
        rust_analyzer = {},
        svelte = {},
        yamlls = {},
        jsonls = {},
        terraformls = {},
        marksman = {},
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
        end,
      })
    end,
  },
}
