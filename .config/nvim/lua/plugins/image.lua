return {
  {
    "3rd/image.nvim",
    -- Render images (visual-regression PNGs, inline markdown) directly in editor
    -- buffers via the kitty graphics protocol. Only enabled under Ghostty (see
    -- term_caps); elsewhere open-external.lua opens the OS viewer.
    cond = require("config.term_caps").inline_images_supported,
    opts = {
      backend = "kitty",
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
