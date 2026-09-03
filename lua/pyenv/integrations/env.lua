--- Exports the active environment into `vim.env`, so `:terminal`, `:!`,
--- `vim.system()` and anything else Neovim spawns agrees with the editor.
local M = {}

--- The `bin` directory this module last prepended to PATH. Tracked so it can be
--- removed before the next one is added: without this, every switch leaks
--- another stale directory onto PATH until the wrong interpreter wins.
---@type string?
local applied_bin = nil

---Rebuild PATH with `bin` at the front, having removed both our previous entry
---and any pre-existing copy of `bin`.
---@param bin string?
local function repath(bin)
  local entries = {}
  for entry in vim.gsplit(vim.env.PATH or "", ":", { plain = true }) do
    -- Empty entries mean "current directory" in POSIX and are a hazard; dropping
    -- them while rebuilding is a small bonus.
    if entry ~= "" and entry ~= applied_bin and entry ~= bin then
      entries[#entries + 1] = entry
    end
  end
  if bin then
    table.insert(entries, 1, bin)
  end
  vim.env.PATH = table.concat(entries, ":")
  applied_bin = bin
end

---@class pyenv.EnvOpts
---@field set_path        boolean?
---@field set_virtual_env boolean?

---Export `resolution` into the editor's environment.
---@param resolution pyenv.Resolution
---@param opts pyenv.EnvOpts?
function M.apply(resolution, opts)
  opts = opts or {}

  if opts.set_path then
    repath(resolution.prefix and (resolution.prefix .. "/bin") or nil)
  end

  -- Only pyenv-managed environments have a name pyenv understands. Exporting
  -- PYENV_VERSION=".venv" would make every pyenv subprocess fail.
  local pyenv_managed = resolution.kind == "version" or resolution.kind == "virtualenv"
  vim.env.PYENV_VERSION = pyenv_managed and not resolution.missing and resolution.version or nil

  if opts.set_virtual_env then
    local is_venv = resolution.kind == "virtualenv" or resolution.kind == "venv"
    vim.env.VIRTUAL_ENV = is_venv and resolution.prefix or nil
  end
end

---Remove this module's PATH entry and forget it. Other variables are left as
---they are; activating a different environment overwrites them.
function M.reset()
  repath(nil)
end

return M
