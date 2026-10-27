return {
  "saghen/blink.cmp",
  version = "1.*", -- prebuilt binaries, no Rust toolchain needed
  event = "InsertEnter",
  opts = {
    keymap = { preset = "default" }, -- use "enter" to accept with <CR>
    sources = { default = { "lsp", "path", "snippets", "buffer" } },
  },
}
