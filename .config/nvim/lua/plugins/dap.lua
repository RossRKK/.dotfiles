return {
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      "rcarriga/nvim-dap-ui",
      "nvim-neotest/nvim-nio",
      "williamboman/mason.nvim",
      "jay-babu/mason-nvim-dap.nvim",
    },
    config = function()
      local dap = require("dap")
      local dapui = require("dapui")

      require("mason-nvim-dap").setup({
        ensure_installed = { "python", "codelldb", "js" },
        automatic_installation = true,
        handlers = {},
      })

      dapui.setup({
        layouts = {
          {
            elements = {
              { id = "scopes",      size = 0.4 },
              { id = "breakpoints", size = 0.2 },
              { id = "stacks",      size = 0.2 },
              { id = "watches",     size = 0.2 },
            },
            size = 40,
            position = "left",
          },
          {
            elements = {
              { id = "repl",    size = 0.5 },
              { id = "console", size = 0.5 },
            },
            size = 12,
            position = "bottom",
          },
        },
      })

      -- Auto open/close dapui with debug session
      dap.listeners.after.event_initialized["dapui_config"] = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated["dapui_config"] = function()
        dapui.close()
      end
      dap.listeners.before.event_exited["dapui_config"] = function()
        dapui.close()
      end

      -- Keymaps
      local map = vim.keymap.set
      map("n", "<F5>",       dap.continue,          { desc = "Debug: continue" })
      map("n", "<F10>",      dap.step_over,         { desc = "Debug: step over" })
      map("n", "<F11>",      dap.step_into,         { desc = "Debug: step into" })
      map("n", "<F12>",      dap.step_out,          { desc = "Debug: step out" })
      map("n", "<leader>b",  dap.toggle_breakpoint, { desc = "Toggle breakpoint" })
      map("n", "<leader>B",  function()
        dap.set_breakpoint(vim.fn.input("Breakpoint condition: "))
      end, { desc = "Conditional breakpoint" })
      map("n", "<leader>du", dapui.toggle,          { desc = "Toggle debug UI" })
    end,
  },
}
