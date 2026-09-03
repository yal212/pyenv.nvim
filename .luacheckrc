-- luacheck configuration for pyenv.nvim
std = "luajit"
cache = true
codes = true

-- Neovim globals
read_globals = {
  "vim",
}

globals = {
  "vim.g",
  "vim.b",
  "vim.w",
  "vim.o",
  "vim.bo",
  "vim.wo",
  "vim.env",
}

-- busted globals in the spec tree
files["spec/"] = {
  -- Tests swap vim.notify out to capture messages.
  globals = { "vim.notify" },
  read_globals = {
    "describe", "it", "before_each", "after_each",
    "setup", "teardown", "pending", "assert",
    "spy", "stub", "mock",
  },
}

ignore = {
  "212", -- unused argument (common for callback signatures)
}

max_line_length = 120
