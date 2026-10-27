return {
  "stevearc/conform.nvim",
  event = "BufWritePre",
  opts = {
    formatters_by_ft = {
      python = { "ruff_organize_imports", "ruff_format" },
      sh = { "shfmt" },
      bash = { "shfmt" },
      -- yaml has no entry: lsp_format = "fallback" below uses yamlls
    },
    formatters = {
      shfmt = { prepend_args = { "-i", "2" } },
    },
    format_on_save = { timeout_ms = 1000, lsp_format = "fallback" },
  },
}
