-- Minimal config for trying pyenv.nvim in isolation:
--   nvim --clean -u spec/minimal_init.lua
-- Point PYENV_ROOT at a real or fixture pyenv installation first.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
