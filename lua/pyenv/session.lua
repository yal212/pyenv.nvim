--- State that describes what this plugin has done to the *process*, kept in
--- `vim.g` rather than in module locals.
---
--- Module state does not survive a reload -- `:Lazy reload pyenv.nvim` drops the
--- plugin's modules and requires them afresh -- but the things this state
--- describes are process-wide and do. A fresh instance holding module locals
--- therefore starts out believing it has changed nothing, while the process
--- still carries its predecessor's exports. `vim.g` outlives the modules and
--- closes that gap.
local M = {}

---The environment as it was before this plugin touched it.
---
---Taken once per Neovim process and never re-taken. Resolution must read these
---rather than the live values: the plugin exports `PYENV_VERSION`, `VIRTUAL_ENV`
---and `PATH` itself, so reading the live environment back would let a value it
---wrote on one activation win as a "shell" or "project venv" match on the next --
---pinning the whole session to whatever the first directory happened to resolve
---to.
---
---`host_prog` is here for a different reason: nothing resolves from it, but the
---plugin overwrites `g:python3_host_prog` and has to be able to put back the
---value the user set for themselves rather than clearing it outright.
---@return { version: string?, virtual_env: string?, path: string?, host_prog: string? }
function M.original()
  if vim.g.pyenv_env_snapshot == nil then
    vim.g.pyenv_env_snapshot = {
      version = vim.env.PYENV_VERSION,
      virtual_env = vim.env.VIRTUAL_ENV,
      path = vim.env.PATH,
      host_prog = vim.g.python3_host_prog,
    }
  end
  return vim.g.pyenv_env_snapshot
end

---The `bin` directory this plugin last prepended to PATH, if any.
---@return string?
function M.path_entry()
  return vim.g.pyenv_path_entry
end

---@param bin string? nil once nothing of ours is on PATH any more
function M.set_path_entry(bin)
  vim.g.pyenv_path_entry = bin
end

---Forget everything, so the next `original()` takes a fresh snapshot. Nothing in
---the plugin calls this; it exists for tests, which need each case to start from
---the environment they just built.
function M.forget()
  vim.g.pyenv_env_snapshot = nil
  vim.g.pyenv_path_entry = nil
end

return M
