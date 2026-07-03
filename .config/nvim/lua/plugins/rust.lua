return {
  {
    -- Owns rust-analyzer and Rust debugging. `:RustLsp debuggables` asks
    -- rust-analyzer for the crate's runnable targets, builds the right one, and
    -- launches it under codelldb (installed via mason) — no manual exe path.
    "mrcjkb/rustaceanvim",
    lazy = false,
  },
}
