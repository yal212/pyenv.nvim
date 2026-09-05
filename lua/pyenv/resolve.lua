--- Works out which Python is active, and - just as importantly - why.
---
--- Every input is injected rather than read from the environment, so the whole
--- chain is testable against fixture directories with no pyenv installed.
local M = {}

local envs = require("pyenv.envs")

---@class pyenv.Resolution
---@field version     string  "3.12.4" | "proj-env" | "system"
---@field python      string? absolute interpreter path; never a shim
---@field prefix      string? absolute environment root
---@field kind        "version"|"virtualenv"|"venv"|"system"
---@field origin      "override"|"shell"|"local"|"project_venv"|"global"|"system"
---@field origin_file string? the file or directory that decided it
---@field parent      string? for virtualenvs, the version they were created from
---@field missing     boolean? requested by name but not installed

---@class pyenv.ResolveOpts
---@field root        string  `$PYENV_ROOT`
---@field cwd         string  directory to resolve from
---@field override    string? name chosen explicitly by the user
---@field shell       string? value of `PYENV_VERSION`
---@field virtual_env string? value of `VIRTUAL_ENV`
---@field path        string? `PATH` to search for system python
---@field order       string[]? step names, in priority order

---The default chain. Note that `project_venv` sits *above* `global`: a global
---pyenv version is a machine-wide default, whereas a project-local .venv is
---scoped to the code in front of you and is nearly always what was intended.
---An explicit `.python-version` still outranks both.
M.DEFAULT_ORDER = { "override", "shell", "local", "project_venv", "global", "system" }

---Read the first meaningful version from a `.python-version`-style file.
---A file may list several versions; pyenv treats lines beginning with `#` as
---comments and the first entry as the active one.
---@param file string
---@return string?
local function read_version_file(file)
  if vim.fn.filereadable(file) == 0 then
    return nil
  end
  for _, line in ipairs(vim.fn.readfile(file)) do
    local trimmed = vim.trim(line)
    if trimmed ~= "" and not trimmed:match("^#") then
      return trimmed
    end
  end
  return nil
end

---Find the first real python on `path`, skipping pyenv's shims directory.
---A shim is a bash script: pyright cannot introspect it and debugpy cannot exec
---it as an adapter host, so it must never be handed out as an interpreter.
---@param path string?
---@param root string?
---@return string?
local function system_python(path, root)
  local shims = root and (vim.fs.normalize(root) .. "/shims") or nil
  for dir in vim.gsplit(path or "", ":", { plain = true }) do
    if dir ~= "" and vim.fs.normalize(dir) ~= shims then
      for _, exe in ipairs({ "python3", "python" }) do
        local candidate = dir .. "/" .. exe
        if vim.fn.executable(candidate) == 1 then
          return candidate
        end
      end
    end
  end
  return nil
end

---@param opts pyenv.ResolveOpts
---@param origin string
---@param origin_file string?
---@return pyenv.Resolution
local function system_resolution(opts, origin, origin_file)
  return {
    version = "system",
    python = system_python(opts.path, opts.root),
    kind = "system",
    origin = origin,
    origin_file = origin_file,
  }
end

---Turn a version *name* into a resolution.
---@param opts pyenv.ResolveOpts
---@param name string
---@param origin string
---@param origin_file string?
---@return pyenv.Resolution
local function from_name(opts, name, origin, origin_file)
  if name == "system" then
    return system_resolution(opts, origin, origin_file)
  end

  local env = envs.find(opts.root, name)
  if env then
    return {
      version = env.name,
      python = env.python,
      prefix = env.prefix,
      kind = env.kind,
      parent = env.parent,
      origin = origin,
      origin_file = origin_file,
    }
  end

  -- The name was requested but is not installed. Report that rather than
  -- quietly falling through to system python, which is precisely the silent
  -- wrong-interpreter behaviour this plugin exists to eliminate.
  local prefix = vim.fs.normalize(opts.root) .. "/versions/" .. name
  return {
    version = name,
    python = prefix .. "/bin/python",
    prefix = prefix,
    kind = "version",
    origin = origin,
    origin_file = origin_file,
    missing = true,
  }
end

---Search upward from `cwd` for a directory-shaped virtualenv.
---@param opts pyenv.ResolveOpts
---@return pyenv.Resolution?
local function venv_in_project(opts)
  -- Both names go into one search. `vim.fs.find` walks up a directory at a time
  -- and stats every name at each level, so the results are nearest-first across
  -- both names, and `.venv` still beats `venv` inside a single directory.
  -- Searching for `.venv` all the way to `/` before trying `venv` at all would
  -- let a stray `.venv` in $HOME capture every `venv`-using project under it.
  --
  -- No `limit = 1`: a venv-shaped directory with no usable interpreter must be
  -- skipped in favour of the next candidate, not treated as the answer.
  local candidates = vim.fs.find({ ".venv", "venv" }, {
    upward = true,
    path = opts.cwd,
    type = "directory",
    limit = math.huge,
  })
  for _, found in ipairs(candidates) do
    local python = found .. "/bin/python"
    if vim.fn.executable(python) == 1 then
      return {
        version = vim.fs.basename(found),
        python = python,
        prefix = found,
        kind = "venv",
        origin = "project_venv",
        origin_file = found,
      }
    end
  end

  local active = opts.virtual_env
  if active and active ~= "" and vim.fn.executable(active .. "/bin/python") == 1 then
    return {
      version = vim.fs.basename(active),
      python = active .. "/bin/python",
      prefix = active,
      kind = "venv",
      origin = "project_venv",
      origin_file = active,
    }
  end
  return nil
end

---Each step returns a resolution, or nil to defer to the next step.
---@type table<string, fun(opts: pyenv.ResolveOpts): pyenv.Resolution?>
local STEPS = {
  override = function(opts)
    return opts.override and opts.override ~= "" and from_name(opts, opts.override, "override", nil)
      or nil
  end,

  shell = function(opts)
    return opts.shell and opts.shell ~= "" and from_name(opts, opts.shell, "shell", nil) or nil
  end,

  ["local"] = function(opts)
    local file = vim.fs.find(".python-version", {
      upward = true,
      path = opts.cwd,
      type = "file",
      limit = 1,
    })[1]
    if not file then
      return nil
    end
    local name = read_version_file(file)
    return name and from_name(opts, name, "local", file) or nil
  end,

  project_venv = venv_in_project,

  global = function(opts)
    local file = vim.fs.normalize(opts.root) .. "/version"
    local name = read_version_file(file)
    return name and from_name(opts, name, "global", file) or nil
  end,

  system = function(opts)
    return system_resolution(opts, "system", nil)
  end,
}

---Resolve the active environment.
---@param opts pyenv.ResolveOpts
---@return pyenv.Resolution
function M.resolve(opts)
  for _, step in ipairs(opts.order or M.DEFAULT_ORDER) do
    local run = STEPS[step]
    if run then
      local resolution = run(opts)
      if resolution then
        return resolution
      end
    end
  end
  -- Reachable only when a caller supplies an order that omits `system`.
  return system_resolution(opts, "system", nil)
end

return M
