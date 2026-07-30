return {
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      "rcarriga/nvim-dap-ui",
      "nvim-neotest/nvim-nio",
    },
    config = function()
      local dap = require("dap")
      local dapui = require("dapui")

      -- Adapter binaries come from Nix (base.nix), not mason: codelldb and
      -- js-debug are on PATH. Rust debugging doesn't use the codelldb adapter
      -- defined here -- rustaceanvim discovers codelldb itself (see <F5>) --
      -- but c/cpp sessions started via plain dap.continue() do.
      dap.adapters.codelldb = {
        type = "server",
        port = "${port}",
        executable = {
          command = "codelldb",
          args = { "--port", "${port}" },
        },
      }

      dap.adapters["pwa-node"] = {
        type = "server",
        host = "localhost",
        port = "${port}",
        executable = {
          command = "js-debug",
          args = { "${port}" },
        },
      }
      for _, ft in ipairs({ "javascript", "typescript" }) do
        dap.configurations[ft] = {
          {
            type = "pwa-node",
            request = "launch",
            name = "Launch file",
            program = "${file}",
            cwd = "${workspaceFolder}",
          },
        }
      end

      -- Python: debug with the uv .venv interpreter so project packages
      -- (hwdescription, system modules) import under the debugger.
      local venv_python = require("util.venv").python
      dap.adapters.python = {
        type = "executable",
        command = venv_python() or "python",
        args = { "-m", "debugpy.adapter" },
      }
      dap.configurations.python = {
        {
          type = "python",
          request = "launch",
          name = "Launch file (venv)",
          program = "${file}",
          pythonPath = function()
            return venv_python() or "python"
          end,
          console = "integratedTerminal",
          cwd = "${workspaceFolder}",
        },
      }

      dapui.setup({
        layouts = {
          {
            elements = {
              { id = "scopes", size = 0.4 },
              { id = "breakpoints", size = 0.2 },
              { id = "stacks", size = 0.2 },
              { id = "watches", size = 0.2 },
            },
            size = 40,
            position = "left",
          },
          {
            elements = {
              { id = "repl", size = 0.5 },
              { id = "console", size = 0.5 },
            },
            size = 12,
            position = "bottom",
          },
        },
      })

      -- Run the debugger in its own tab so it never disturbs the editing layout
      -- (tree / editor / terminal). The tab closes when the session ends.
      local debug_tab
      dap.listeners.after.event_initialized["dapui_config"] = function()
        vim.cmd("tabnew")
        debug_tab = vim.api.nvim_get_current_tabpage()
        dapui.open()
      end
      local function close_debug_view()
        dapui.close()
        if debug_tab and vim.api.nvim_tabpage_is_valid(debug_tab) then
          pcall(vim.cmd, vim.api.nvim_tabpage_get_number(debug_tab) .. "tabclose")
        end
        debug_tab = nil
      end
      dap.listeners.before.event_terminated["dapui_config"] = close_debug_view
      dap.listeners.before.event_exited["dapui_config"] = close_debug_view

      -- Keymaps
      local map = vim.keymap.set
      map("n", "<F5>", function()
        if dap.session() then
          dap.continue() -- resume a running session
        elseif vim.bo.filetype == "rust" then
          vim.cmd("RustLsp debuggables") -- rustaceanvim resolves the executable
        else
          dap.continue() -- start via the filetype's launch config
        end
      end, { desc = "Debug: start / continue" })
      map("n", "<F10>", dap.step_over, { desc = "Debug: step over" })
      map("n", "<F11>", dap.step_into, { desc = "Debug: step into" })
      map("n", "<F12>", dap.step_out, { desc = "Debug: step out" })
      map("n", "<leader>b", dap.toggle_breakpoint, { desc = "Toggle breakpoint" })
      map("n", "<leader>B", function()
        dap.set_breakpoint(vim.fn.input("Breakpoint condition: "))
      end, { desc = "Conditional breakpoint" })
      map("n", "<leader>du", dapui.toggle, { desc = "Toggle debug UI" })
    end,
  },
}
