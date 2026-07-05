return {
  {
    "3rd/image.nvim",
    -- Render images (visual-regression PNGs, inline markdown) directly in
    -- editor buffers. Uses whatever protocol the current terminal speaks:
    -- Kitty under Ghostty on Linux, Sixel under Windows Terminal (WSL).
    -- Detection: Windows Terminal exports WT_SESSION; everything else is
    -- assumed Kitty-capable (Ghostty / WezTerm / kitty).
    opts = {
      backend = vim.env.WT_SESSION and "sixel" or "kitty",
      -- magick_cli shells out to the ImageMagick CLI (already installed),
      -- so no `magick` luarock / luarocks build is required.
      processor = "magick_cli",
      integrations = {
        markdown = {
          enabled = true,
          only_render_image_at_cursor = false,
        },
      },
      max_width = 100,
      max_height = 30,
      -- Keep images from spilling past the window when scrolling/splitting.
      max_width_window_percentage = 100,
      max_height_window_percentage = 50,
    },
  },
}
