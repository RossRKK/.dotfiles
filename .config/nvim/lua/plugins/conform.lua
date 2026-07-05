return {
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    opts = {
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
        -- prettierd handles the web stack. On markdown it defaults to
        -- proseWrap="preserve", so it won't fight the custom `gq` prose reflow
        -- in autocmds.lua (it keeps your existing line breaks).
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
