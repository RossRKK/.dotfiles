-- Explore a JSON/YAML/TOML buffer as a graph of nested tables (`:Videre`).
-- JSON parsing is built in; the parser plugins add YAML and TOML, which videre
-- picks up on its own when they are on the runtimepath.
return {
  {
    "Owen-Dechow/videre.nvim",
    cmd = "Videre",
    dependencies = {
      "Owen-Dechow/graph_view_yaml_parser",
      "Owen-Dechow/graph_view_toml_parser",
    },
    opts = {},
  },
}
