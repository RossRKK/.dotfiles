return {
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    opts = {
      -- prettierd takes no CLI options -- it reads a project prettier config, or
      -- falls back to PRETTIERD_DEFAULT_CONFIG when a project has none. Point that
      -- at our defaults so bare Markdown reflows prose to 80 and aligns tables;
      -- projects with their own prettier config still win.
      formatters = {
        prettierd = {
          env = {
            PRETTIERD_DEFAULT_CONFIG = vim.fn.stdpath("config") .. "/prettierd-default.json",
          },
        },
      },
      -- Formatter CLIs are auto-installed via mason-tool-installer (see lsp.lua),
      -- except rustfmt (rust toolchain) and terraform (terraform CLI), expected
      -- on PATH. Any filetype not listed falls back to the LSP formatter.
      formatters_by_ft = {
        lua = { "stylua" },
        rust = { "rustfmt" },
        python = { "ruff_organize_imports", "ruff_format" },
        terraform = { "terraform_fmt" },
        tf = { "terraform_fmt" },
        sh = { "shfmt" },
        bash = { "shfmt" },
        -- prettierd handles the web stack and Markdown. `gq`/`gw` in Markdown
        -- route through conform (see autocmds.lua) so reflow uses prettier, which
        -- reflows prose and keeps tables aligned instead of the built-in reflow.
        javascript = { "prettierd" },
        javascriptreact = { "prettierd" },
        typescript = { "prettierd" },
        typescriptreact = { "prettierd" },
        svelte = { "prettierd" },
        json = { "prettierd" },
        jsonc = { "prettierd" },
        yaml = { "prettierd" },
        css = { "prettierd" },
        scss = { "prettierd" },
        html = { "prettierd" },
        markdown = { "prettierd" },
      },
      -- Format on save; fall back to the LSP formatter when no CLI formatter is
      -- configured for the filetype. Delete this block to make formatting
      -- manual-only (:lua require("conform").format()).
      format_on_save = { timeout_ms = 1000, lsp_format = "fallback" },
    },
  },
}
