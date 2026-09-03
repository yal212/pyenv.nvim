rockspec_format = "3.0"
package = "pyenv.nvim"
version = "scm-1"

source = {
  url = "git+https://github.com/yal212/pyenv.nvim",
}

description = {
  summary = "pyenv integration for Neovim",
  detailed = [[
    Resolves the active pyenv environment for the current directory and points
    the language server, debugger and terminals at it. Installs Python versions
    and creates pyenv virtualenvs from inside Neovim. No plugin dependencies.
  ]],
  homepage = "https://github.com/yal212/pyenv.nvim",
  license = "MIT",
  labels = { "neovim", "python", "pyenv", "lsp" },
}

dependencies = {
  "lua >= 5.1",
}

test_dependencies = {
  "busted",
  "nlua",
}

build = {
  type = "builtin",
  copy_directories = { "doc", "plugin" },
}
