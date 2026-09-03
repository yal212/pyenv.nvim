--- Enumeration of the environments installed under a `$PYENV_ROOT`.
---
--- This reads the filesystem directly instead of shelling out to `pyenv versions`.
--- A directory scan costs about a millisecond; `pyenv versions` costs a bash spawn
--- plus a rehash, and it is unavailable entirely when Neovim was launched without
--- pyenv on its `PATH` (routine for GUI launches on macOS).
local M = {}

local uv = vim.uv

---@class pyenv.Env
---@field name      string  short name, e.g. "3.12.4" or "proj-env"
---@field qualified string  pyenv's long name, e.g. "3.12.4/envs/proj-env"
---@field prefix    string  absolute path to the environment root
---@field python    string  absolute path to the interpreter (never a shim)
---@field kind      "version"|"virtualenv"
---@field parent    string? for virtualenvs, the version they were created from

---Split a string into numeric and non-numeric chunks for natural ordering.
---@param s string
---@return (string|number)[]
local function chunks(s)
  local out = {}
  for digits, rest in s:gmatch("(%d*)(%D*)") do
    if digits ~= "" then
      out[#out + 1] = tonumber(digits)
    end
    if rest ~= "" then
      out[#out + 1] = rest
    end
  end
  return out
end

---Order version-like names the way a human reads them, so that 3.9.10 sorts
---before 3.10.0 rather than after it as a plain string comparison would give.
---@param a string
---@param b string
---@return boolean
local function natural_lt(a, b)
  local ca, cb = chunks(a), chunks(b)
  for i = 1, math.max(#ca, #cb) do
    local x, y = ca[i], cb[i]
    if x == nil then
      return true
    elseif y == nil then
      return false
    elseif type(x) ~= type(y) then
      return type(x) == "number"
    elseif x ~= y then
      return x < y
    end
  end
  return false
end

---@param prefix string
---@return string
local function interpreter_for(prefix)
  local python = prefix .. "/bin/python"
  if vim.fn.executable(python) == 1 then
    return python
  end
  local python3 = prefix .. "/bin/python3"
  if vim.fn.executable(python3) == 1 then
    return python3
  end
  -- Report the conventional path even when it is missing; `health` verifies
  -- executability and can then explain precisely what is broken.
  return python
end

---@param prefix string
---@return boolean
local function has_pyvenv_cfg(prefix)
  return uv.fs_stat(prefix .. "/pyvenv.cfg") ~= nil
end

---Derive the parent version from a realpath of the form
---`<root>/versions/<python>/envs/<name>`.
---@param realpath string
---@return string? parent
local function parent_from(realpath)
  return realpath:match("/versions/([^/]+)/envs/[^/]+/?$")
end

---List every environment under `root`, versions first then virtualenvs, each in
---natural order.
---@param root string? absolute path to a `$PYENV_ROOT`
---@return pyenv.Env[]
function M.list(root)
  if not root or root == "" then
    return {}
  end

  local versions_dir = vim.fs.normalize(root) .. "/versions"
  if vim.fn.isdirectory(versions_dir) == 0 then
    return {}
  end

  ---Keyed by resolved real path, so the symlink and the directory it points at
  ---(pyenv-virtualenv always creates both) collapse into a single entry.
  ---@type table<string, pyenv.Env>
  local by_realpath = {}

  ---@param name string     the name to display
  ---@param path string     the path as discovered (possibly a symlink)
  ---@param is_link boolean
  local function record(name, path, is_link)
    local realpath = uv.fs_realpath(path)
    if not realpath or vim.fn.isdirectory(realpath) == 0 then
      return
    end

    local existing = by_realpath[realpath]
    -- A short top-level name beats the qualified `<py>/envs/<name>` form.
    if existing and #existing.name <= #name then
      return
    end

    local parent = parent_from(realpath)
    local kind = (is_link or parent or has_pyvenv_cfg(realpath)) and "virtualenv" or "version"

    by_realpath[realpath] = {
      name = name,
      qualified = parent and (parent .. "/envs/" .. name) or name,
      prefix = realpath,
      python = interpreter_for(realpath),
      kind = kind,
      parent = parent,
    }
  end

  for name, type_ in vim.fs.dir(versions_dir) do
    if type_ == "directory" or type_ == "link" then
      record(name, versions_dir .. "/" .. name, type_ == "link")

      -- Virtualenvs created without a top-level symlink still live under `envs/`.
      local envs_dir = versions_dir .. "/" .. name .. "/envs"
      if vim.fn.isdirectory(envs_dir) == 1 then
        for env_name, env_type in vim.fs.dir(envs_dir) do
          if env_type == "directory" or env_type == "link" then
            record(env_name, envs_dir .. "/" .. env_name, false)
          end
        end
      end
    end
  end

  local list = vim.tbl_values(by_realpath)
  table.sort(list, function(a, b)
    if a.kind ~= b.kind then
      return a.kind == "version"
    end
    return natural_lt(a.name, b.name)
  end)
  return list
end

---Look up a single environment by short or qualified name.
---@param root string?
---@param name string?
---@return pyenv.Env?
function M.find(root, name)
  if not name or name == "" then
    return nil
  end
  for _, env in ipairs(M.list(root)) do
    if env.name == name or env.qualified == name then
      return env
    end
  end
  return nil
end

return M
