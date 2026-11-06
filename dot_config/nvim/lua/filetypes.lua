-- Chezmoi templates (*.tmpl): use the filetype of the name underneath ".tmpl"
--   .chezmoi.toml.tmpl -> toml, run_onchange_x.sh.tmpl -> sh, dot_bashrc.tmpl -> sh
vim.filetype.add({
  pattern = {
    [".*%.tmpl"] = {
      function(path)
        local base = vim.fs.basename(path):gsub("%.tmpl$", "")
        -- strip chezmoi source-state prefixes (dot_bashrc -> .bashrc)
        base = base:gsub("^dot_", "."):gsub("^executable_", ""):gsub("^private_", "")
        return (vim.filetype.match({ filename = base }))
      end,
      { priority = 10 },
    },
  },
})
