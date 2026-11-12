-- nvim-lint for CLI linters that have no language server. Today that's
-- api-linter (Google's AIP linter) on protos, only in repos with an api-linter
-- config, as their CI runs it; buf_ls still serves navigation, completion and
-- formatting there. lazy replays the loading proto's BufReadPost to this group.
return {
  {
    "mfussenegger/nvim-lint",
    ft = "proto",
    config = function()
      local lint = require("lint")
      local api_linter = require("util.api_linter")
      lint.linters.api_linter = function()
        local file = vim.api.nvim_buf_get_name(0)
        return api_linter.linter(assert(api_linter.find_config(file)), file)
      end
      vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
        group = vim.api.nvim_create_augroup("proto_lint", { clear = true }),
        pattern = "*.proto",
        callback = function(ev)
          if api_linter.find_config(vim.api.nvim_buf_get_name(ev.buf)) then
            -- try_lint lints the current buffer, which on :wa isn't the one written.
            vim.api.nvim_buf_call(ev.buf, function()
              lint.try_lint("api_linter")
            end)
          end
        end,
      })
    end,
  },
}
