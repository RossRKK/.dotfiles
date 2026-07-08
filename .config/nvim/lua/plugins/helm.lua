-- Filetype detection for Helm charts. A file is "helm" when it belongs to a
-- chart (a Chart.yaml exists in some ancestor directory) rather than when its
-- path happens to contain a "templates" segment -- chart membership is the real
-- signal and survives non-standard layouts. Chart.yaml/values.yaml stay "yaml"
-- (chart metadata, wanted on yamlls + schema); .tpl/.gotmpl are helm by
-- extension. The "helm" filetype routes buffers to helm_ls (see lsp.lua) and the
-- helm treesitter parser (see treesitter.lua) instead of the yaml ones, which
-- choke on the embedded {{ ... }} Go-template directives.
--
-- Detection lives in init() (lazy.nvim runs every spec's init at startup) rather
-- than in vim-helm's own ftdetect: loading vim-helm on ft="helm" while relying
-- on it to *set* that filetype is circular. vim-helm still loads on the helm
-- filetype for its syntax/indent.
local function belongs_to_helm_chart(path)
  local chart = vim.fs.find("Chart.yaml", {
    upward = true,
    type = "file",
    path = vim.fs.dirname(path),
  })
  return #chart > 0
end

return {
  {
    "towolf/vim-helm",
    ft = "helm",
    init = function()
      vim.filetype.add({
        extension = {
          tpl = "helm",
          gotmpl = "helm",
        },
        pattern = {
          [".*%.ya?ml"] = function(path)
            local name = vim.fs.basename(path)
            if name == "Chart.yaml" or name:match("^values.*%.ya?ml$") then
              return -- chart metadata: leave as yaml
            end
            if belongs_to_helm_chart(path) then
              return "helm"
            end
            -- otherwise fall through to Neovim's builtin yaml detection
          end,
        },
      })
    end,
  },
}
