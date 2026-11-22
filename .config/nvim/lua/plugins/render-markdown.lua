-- render-markdown.nvim: an agent chat's replies drawn as rendered markdown.
-- Only in the chat (AgenticChat, which agentic parses as markdown); files stay raw.
local rerender_on_write -- defined below the spec

local spec = {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    ft = { "AgenticChat" },
    keys = {
      { "<leader>ur", "<cmd>RenderMarkdown toggle<cr>", desc = "Toggle markdown rendering" },
    },
    ---@module 'render-markdown'
    ---@type render.md.UserConfig
    opts = {
      file_types = { "AgenticChat" },
      -- The chat is read while typing in the prompt, so it renders in every mode.
      render_modes = true,
    },
    config = function(_, opts)
      require("render-markdown").setup(opts)
      -- lazy fires FileType again once loaded, so this also takes the chat that loaded it.
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "AgenticChat",
        callback = function(args)
          rerender_on_write(args.buf)
        end,
      })
    end,
  },
}

--- Re-render chat `buf` after each write. agentic streams replies into it from the prompt's
--- window, where render-markdown's own TextChanged never fires; it debounces the renders.
---@param buf integer
function rerender_on_write(buf)
  local queued = false
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      if queued then
        return
      end
      queued = true
      vim.schedule(function()
        queued = false
        if vim.api.nvim_buf_is_valid(buf) then
          require("render-markdown").render({ buf = buf, force = false })
        end
      end)
    end,
  })
end

return spec
