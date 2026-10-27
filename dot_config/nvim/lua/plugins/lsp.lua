-- Servers are installed outside Neovim (no Mason):
--   basedpyright, ruff         -> uv tool (packages.yaml)
--   bash-language-server,
--   yaml-language-server       -> npm via mise (dot_config/mise/config.toml)
--   shellcheck, shfmt          -> apt (packages.yaml)
return {
  "neovim/nvim-lspconfig",
  dependencies = { "saghen/blink.cmp", "b0o/SchemaStore.nvim" },
  config = function()
    vim.lsp.config("*", {
      capabilities = require("blink.cmp").get_lsp_capabilities(),
    })

    -- Python: basedpyright for types, ruff for lint/format/imports
    vim.lsp.config("basedpyright", {
      settings = {
        basedpyright = {
          disableOrganizeImports = true, -- ruff owns this
          analysis = { typeCheckingMode = "standard" }, -- default "recommended" is noisy
        },
      },
    })
    vim.lsp.config("ruff", {
      on_attach = function(client)
        client.server_capabilities.hoverProvider = false -- basedpyright owns hover
      end,
    })

    -- YAML: SchemaStore instead of yamlls's built-in catalog
    vim.lsp.config("yamlls", {
      settings = {
        yaml = {
          schemaStore = { enable = false, url = "" },
          schemas = require("schemastore").yaml.schemas(),
        },
      },
    })

    vim.lsp.enable({ "basedpyright", "ruff", "bashls", "yamlls" })

    -- Neovim 0.11 defaults: K hover, grn rename, gra code action,
    -- grr references, gri implementation. Add the familiar gd:
    vim.keymap.set("n", "gd", vim.lsp.buf.definition, { desc = "Go to definition" })
  end,
}
