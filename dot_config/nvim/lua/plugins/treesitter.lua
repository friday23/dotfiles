return {
  "nvim-treesitter/nvim-treesitter",
  branch = "main",
  lazy = false, -- this plugin does not support lazy-loading
  build = ":TSUpdate",
  config = function()
    -- Install missing parsers on interactive startup. The headless sync
    -- script installs them (and waits) during chezmoi apply.
    if #vim.api.nvim_list_uis() > 0 then
      require("nvim-treesitter").install(require("langs"))
    end

    -- On the main branch, highlighting is enabled per filetype
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "python", "sh", "bash", "yaml", "toml", "json", "lua", "markdown" },
      callback = function()
        pcall(vim.treesitter.start)
      end,
    })
  end,
}
