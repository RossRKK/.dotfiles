-- No Mason: LSP servers, formatters, CLI tools, and debug adapters are
-- installed via Nix (home-manager base.nix) and found on PATH. Servers are
-- enabled explicitly in the lspconfig block below.
return {
  {
    "neovim/nvim-lspconfig",
    dependencies = {
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
        -- helm_ls shells out to yaml-language-server for the embedded YAML,
        -- finding it on PATH (installed via Nix alongside the other servers).
        helm_ls = {},
        -- No binary to install: the GDScript server *is* the Godot editor,
        -- which hosts it on 127.0.0.1:6005 (override with
        -- $GDScript_Port). lspconfig's lsp/gdscript.lua supplies the
        -- vim.lsp.rpc.connect cmd and project.godot root marker. Opening a .gd
        -- file with Godot closed logs a connection error and leaves the buffer
        -- on treesitter highlighting alone -- that's expected, not a misconfig.
        gdscript = {},
        -- nixd evaluates the flake at the workspace root so option names
        -- (programs.fish.*, etc.) complete and hover with docs. The option
        -- exprs are built in before_init from whatever root nixd resolved
        -- (nearest flake.nix), so the same config works in the dotfiles
        -- home-manager flake, a NixOS repo, or any other flake:
        --   home-manager -> the homeConfigurations attr for the current
        --     $USER (usernames differ per machine, so this is unique)
        --   nixos -> nixosConfigurations."<hostname>"
        -- Whichever attr a given flake doesn't export just fails its eval
        -- quietly; the other still provides completion. The "path:" fetcher
        -- reads the directory as-is, so uncommitted (even untracked) files
        -- are seen, at the cost of copying the dir to the store per eval.
        nixd = {
          before_init = function(params, config)
            local root = params.rootPath
            if not root or not vim.uv.fs_stat(root .. "/flake.nix") then
              return
            end
            local flake = ('(builtins.getFlake "path:%s")'):format(root)
            config.settings = vim.tbl_deep_extend("force", config.settings or {}, {
              nixd = {
                options = {
                  ["home-manager"] = {
                    expr = ('(let f = %s; '
                      .. 'name = builtins.head (builtins.filter '
                      .. '(n: builtins.match "%s@.*" n != null) '
                      .. '(builtins.attrNames f.homeConfigurations)); '
                      .. 'in f.homeConfigurations.${name}.options)'):format(flake, vim.env.USER),
                  },
                  nixos = {
                    expr = ('%s.nixosConfigurations."%s".options'):format(flake, vim.fn.hostname()),
                  },
                },
              },
            })
          end,
        },
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
