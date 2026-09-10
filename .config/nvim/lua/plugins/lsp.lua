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
      -- Resolved per client in before_init, from that client's root_dir: one
      -- nvim holds several workspace tabs (config.workspace), each on its own
      -- checkout with its own .venv, so a single path picked at startup would
      -- hand every tab the venv of whichever directory nvim was launched from.
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
          },
          before_init = function(_, config)
            config.settings = vim.tbl_deep_extend("force", config.settings or {}, {
              python = { pythonPath = venv_python(config.root_dir) },
            })
          end,
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

      -- A workspace tab is opened before its checkout has been `uv sync`ed, so
      -- basedpyright starts with no venv (or, searching upward, the main
      -- checkout's) and every cross-package import is unresolved. Pyright
      -- reloads python.pythonPath on workspace/didChangeConfiguration and
      -- re-resolves imports in place -- the same path lspconfig's
      -- :LspPyrightSetPythonPath takes -- so no restart: recompute the venv
      -- from the client's root and push it when it differs. Cheap (one upward
      -- stat walk, no process), so it runs on every python BufEnter and on
      -- FocusGained, which is the moment you come back from the pane where the
      -- sync ran. :PyVenvRefresh does the same by hand.
      local function refresh_venv(bufnr)
        for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr, name = "basedpyright" })) do
          local py = venv_python(client.root_dir)
          local settings = client.settings or {}
          if py and py ~= vim.tbl_get(settings, "python", "pythonPath") then
            settings.python = vim.tbl_deep_extend("force", settings.python or {}, { pythonPath = py })
            client.settings = settings
            client:notify("workspace/didChangeConfiguration", { settings = nil })
            vim.notify("basedpyright: " .. py, vim.log.levels.INFO)
          end
        end
      end
      vim.api.nvim_create_autocmd({ "BufEnter", "FocusGained" }, {
        callback = function(ev)
          if vim.bo[ev.buf].filetype == "python" then
            refresh_venv(ev.buf)
          end
        end,
      })
      vim.api.nvim_create_user_command("PyVenvRefresh", function()
        refresh_venv(vim.api.nvim_get_current_buf())
      end, { desc = "Re-point basedpyright at the nearest .venv" })

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
          -- inc-rename (plugins/inc-rename.lua) instead of vim.lsp.buf.rename:
          -- an expr mapping, so it drops ":IncRename <cword>" on the cmdline
          -- with the old name prefilled and previews the edit as you retype it.
          -- Set directly rather than via `map`, which doesn't pass expr.
          vim.keymap.set("n", "<leader>rn", function()
            return ":IncRename " .. vim.fn.expand("<cword>")
          end, { buffer = ev.buf, expr = true, desc = "Rename" })
          -- Rename the *file* in the current buffer, letting the server rewrite
          -- the imports that point at it (workspace/willRenameFiles). Same
          -- machinery neo-tree's rename fires -- see plugins/explorer.lua.
          map("<leader>rf", function()
            Snacks.rename.rename_file()
          end, "Rename file")
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
