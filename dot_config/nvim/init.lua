local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

vim.g.mapleader = " "

-- Neovim 0.11 turned inline diagnostic text off by default
vim.diagnostic.config({ virtual_text = true, severity_sort = true })

-- Loads every file in lua/plugins/
require("lazy").setup("plugins")
