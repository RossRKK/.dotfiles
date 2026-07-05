return {
  {
    "nvim-telescope/telescope.nvim",
    -- Both 0.1.x and master still call nvim-treesitter master-only functions
    -- (parsers.ft_to_lang/get_parser) in the previewer, which don't exist on the
    -- nvim-treesitter main branch we run -- so preview highlighting is broken on
    -- either. We patch ts_highlighter to native vim.treesitter in config() below,
    -- which fixes both; master is kept simply for its newer features/fixes.
    branch = "master",
    dependencies = {
      "nvim-lua/plenary.nvim",
      {
        "nvim-telescope/telescope-fzf-native.nvim",
        build = "make",
      },
    },
    config = function()
      local telescope = require("telescope")
      telescope.setup({
        defaults = {
          layout_strategy = "horizontal",
          sorting_strategy = "ascending",
          layout_config = { prompt_position = "top" },
        },
      })
      telescope.load_extension("fzf")

      -- Telescope's previewer highlighter (both 0.1.x and master) still calls the
      -- nvim-treesitter *master* API (parsers.ft_to_lang/get_parser), which no
      -- longer exists now that nvim-treesitter is on the `main`-branch rewrite --
      -- so previews get no treesitter highlighting (e.g. <leader>fg). Replace
      -- telescope's ts_highlighter with native vim.treesitter, matching how
      -- treesitter.lua highlights ordinary buffers. Returns true so the caller
      -- doesn't fall back to regex; false (unknown/uninstalled lang) lets it.
      local putils = require("telescope.previewers.utils")
      putils.ts_highlighter = function(bufnr, ft)
        local lang = vim.treesitter.language.get_lang(ft or "")
        if not lang then
          return false
        end
        return pcall(vim.treesitter.start, bufnr, lang)
      end

      local builtin = require("telescope.builtin")
      vim.keymap.set("n", "<C-p>", builtin.find_files, { desc = "Find files" })
      vim.keymap.set("n", "<leader>fg", builtin.live_grep, { desc = "Live grep" })
      vim.keymap.set("n", "<leader>fb", builtin.buffers, { desc = "Find buffers" })
      vim.keymap.set("n", "<leader>fh", builtin.help_tags, { desc = "Help tags" })
    end,
  },
}
