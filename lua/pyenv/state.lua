--- Session state: the active resolution, plus remembered per-project choices.
---
--- A manual pick is persisted to a cache file keyed by project root rather than
--- written into the project itself. Creating a tracked `.python-version` in
--- someone's repository as a side effect of choosing from a menu is a surprise;
--- `:Pyenv local` exists for when that is actually wanted.
local M = {}

local uv = vim.uv

--- Markers that identify a project root, nearest first in spirit: the presence
--- of any one of them means "this directory is the top of a Python project".
local PROJECT_MARKERS = {
  ".python-version",
  "pyproject.toml",
  "setup.py",
  "setup.cfg",
  "requirements.txt",
  ".venv",
  ".git",
}

---@class pyenv.StateOpts
---@field path    string?  cache file location
---@field enabled boolean? whether to persist to disk

---@type table<string, string>
local overrides = {}
---@type pyenv.Resolution?
local active = nil
---@type pyenv.StateOpts
local opts = {}

---@return string
local function cache_path()
  return opts.path or (vim.fn.stdpath("data") .. "/pyenv.nvim/projects.json")
end

---@return boolean
local function persisting()
  return opts.enabled ~= false
end

---@param project string
---@return string
local function key(project)
  return vim.fs.normalize(project)
end

---Read the cache. A corrupt or unexpected file is treated as an empty cache
---rather than an error: losing a remembered choice is a far better outcome than
---breaking startup, and the next write repairs the file.
local function load()
  overrides = {}
  if not persisting() then
    return
  end

  local path = cache_path()
  if vim.fn.filereadable(path) == 0 then
    return
  end

  local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
  if not ok or type(decoded) ~= "table" then
    return
  end

  for project, name in pairs(decoded) do
    if type(project) == "string" and type(name) == "string" then
      overrides[project] = name
    end
  end
end

---Write the cache via a temporary file and a rename, so an interrupted write
---cannot leave a half-written file behind.
local function save()
  if not persisting() then
    return
  end

  local path = cache_path()
  vim.fn.mkdir(vim.fs.dirname(path), "p")

  local ok, encoded = pcall(vim.json.encode, overrides)
  if not ok then
    return
  end

  local tmp = path .. ".tmp"
  local fd = uv.fs_open(tmp, "w", tonumber("600", 8))
  if not fd then
    return
  end
  uv.fs_write(fd, encoded)
  uv.fs_close(fd)
  uv.fs_rename(tmp, path)
end

---Re-initialise. Called by `setup()` and by tests.
---@param new_opts pyenv.StateOpts?
function M.reset(new_opts)
  opts = new_opts or {}
  active = nil
  load()
end

---@param project string
---@return string?
function M.get_override(project)
  return overrides[key(project)]
end

---@param project string
---@param name string
function M.set_override(project, name)
  overrides[key(project)] = name
  save()
end

---@param project string
function M.clear_override(project)
  overrides[key(project)] = nil
  save()
end

---The most recently activated resolution. Session-only; never persisted,
---because it is derived state that must be recomputed against the real
---filesystem on every start.
---@return pyenv.Resolution?
function M.current()
  return active
end

---@param resolution pyenv.Resolution?
function M.set_current(resolution)
  active = resolution
end

---Find the top of the project containing `dir`, falling back to `dir` itself.
---@param dir string
---@return string
function M.project_root(dir)
  return vim.fs.root(dir, PROJECT_MARKERS) or vim.fs.normalize(dir)
end

return M
