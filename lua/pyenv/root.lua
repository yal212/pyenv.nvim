--- Locates `$PYENV_ROOT` and the `pyenv` executable.
local M = {}

---@class pyenv.RootOpts
---@field configured string? root from user configuration
---@field env        string? value of `$PYENV_ROOT`
---@field home       string? value of `$HOME`

---@param value string?
---@return string?
local function expand(value)
  if not value or value == "" then
    return nil
  end
  return vim.fs.normalize(vim.fn.expand(value))
end

---Work out which directory is the pyenv root.
---
---An explicitly configured or exported root is honoured even if it does not
---exist, matching pyenv's own behaviour; `health` reports the problem rather
---than this quietly picking somewhere else. The implicit `~/.pyenv` default is
---only used when it actually exists, so a nil return reliably means "no pyenv
---on this machine".
---@param opts pyenv.RootOpts?
---@return string?
function M.find(opts)
  opts = opts or {}

  local explicit = expand(opts.configured) or expand(opts.env)
  if explicit then
    return explicit
  end

  local home = expand(opts.home) or expand(vim.env.HOME)
  if home then
    local default = home .. "/.pyenv"
    if vim.fn.isdirectory(default) == 1 then
      return default
    end
  end
  return nil
end

---Find the `pyenv` executable.
---
---`<root>/bin/pyenv` is checked first: a git-cloned pyenv ships its own `bin/`,
---so management commands keep working even when Neovim was launched without
---pyenv on its `PATH`.
---@param root string?
---@param path string? `PATH` to search; defaults to the current one
---@return string?
function M.binary(root, path)
  if root and root ~= "" then
    local candidate = vim.fs.normalize(root) .. "/bin/pyenv"
    if vim.fn.executable(candidate) == 1 then
      return candidate
    end
  end

  for dir in vim.gsplit(path or vim.env.PATH or "", ":", { plain = true }) do
    if dir ~= "" then
      local candidate = dir .. "/pyenv"
      if vim.fn.executable(candidate) == 1 then
        return candidate
      end
    end
  end
  return nil
end

return M
