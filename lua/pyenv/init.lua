--- Public API. `require("pyenv")`
---
--- Calling `setup()` is optional; the plugin auto-initialises with defaults.
local M = {}

local config = require("pyenv.config")
local envs = require("pyenv.envs")
local env_integration = require("pyenv.integrations.env")
local resolve = require("pyenv.resolve")
local root = require("pyenv.root")
local state = require("pyenv.state")

--- The environment as it was before this plugin touched it.
---
--- Resolution must read these rather than the live values. The plugin exports
--- `PYENV_VERSION`, `VIRTUAL_ENV` and `PATH` itself, so reading the live
--- environment back would let a value it wrote on one activation win as a
--- "shell" or "project venv" match on the next — pinning the whole session to
--- whatever the first directory happened to resolve to.
---@type { version: string?, virtual_env: string?, path: string? }
local original = {}

local function snapshot()
  original = {
    version = vim.env.PYENV_VERSION,
    virtual_env = vim.env.VIRTUAL_ENV,
    path = vim.env.PATH,
  }
end

snapshot()

---Apply user configuration. Optional, but must run before anything activates —
---which is the case when called from a plugin spec or `init.lua`.
---@param opts table?
---@return pyenv.Config
function M.setup(opts)
  local cfg = config.setup(opts)
  -- Only while nothing is active. Re-taking the snapshot after an activation
  -- would capture the plugin's own exports and pin every later resolution to
  -- them, which is the whole failure `original` exists to prevent. Checked
  -- before `state.reset` below, which clears exactly this signal.
  if not state.current() then
    snapshot()
  end
  state.reset({ path = cfg.cache.path, enabled = cfg.cache.enabled })
  return cfg
end

---The pyenv root in use, or nil when there is no pyenv on this machine.
---@return string?
function M.root()
  return root.find({ configured = config.get().root, env = vim.env.PYENV_ROOT })
end

---Every environment pyenv has installed.
---@return pyenv.Env[]
function M.list()
  return envs.list(M.root())
end

---Work out which environment applies to `cwd`, without activating it.
---@param cwd string?
---@return pyenv.Resolution
function M.resolve(cwd)
  local cfg = config.get()
  cwd = cwd or vim.fn.getcwd()
  return resolve.resolve({
    root = M.root() or "",
    cwd = cwd,
    override = state.get_override(state.project_root(cwd)),
    shell = original.version,
    virtual_env = original.virtual_env,
    path = original.path,
    order = cfg.resolution_order,
  })
end

---@param a pyenv.Resolution?
---@param b pyenv.Resolution?
---@return boolean
local function differs(a, b)
  if not a or not b then
    return true
  end
  return a.version ~= b.version or a.prefix ~= b.prefix or a.origin ~= b.origin
end

---@param resolution pyenv.Resolution
---@param previous pyenv.Resolution?
---@param cfg pyenv.Config
---@param notify fun(msg: string, level: integer)
local function announce(resolution, previous, cfg, notify)
  if cfg.notify == false then
    return
  end

  if resolution.missing then
    notify(
      ("pyenv.nvim: %s is not installed%s"):format(
        resolution.version,
        resolution.origin_file and (" (requested by " .. resolution.origin_file .. ")") or ""
      ),
      vim.log.levels.WARN
    )
    return
  end

  if cfg.notify == "errors" then
    return
  end
  if cfg.notify == "changes" and not differs(resolution, previous) then
    return
  end
  notify("pyenv.nvim: " .. M.status(resolution), vim.log.levels.INFO)
end

---@class pyenv.ActivateOpts
---@field name   string? environment to pin for this project
---@field cwd    string? directory to resolve from; defaults to the current one
---@field notify fun(msg: string, level: integer)? injection seam for tests

---Resolve the environment for `cwd` and wire it into the editor.
---@param opts pyenv.ActivateOpts?
---@return pyenv.Resolution
function M.activate(opts)
  opts = opts or {}
  local cfg = config.get()
  local cwd = opts.cwd or vim.fn.getcwd()

  if opts.name then
    state.set_override(state.project_root(cwd), opts.name)
  end

  local resolution = M.resolve(cwd)
  local previous = state.current()
  state.set_current(resolution)

  env_integration.apply(resolution, cfg.terminal)

  if cfg.lsp.enabled then
    require("pyenv.integrations.lsp").apply(resolution, cfg.lsp)
  end
  if cfg.dap.enabled then
    require("pyenv.integrations.dap").apply(resolution)
  end
  if cfg.python3_host_prog and resolution.python and not resolution.missing then
    vim.g.python3_host_prog = resolution.python
  end

  announce(resolution, previous, cfg, opts.notify or vim.notify)
  return resolution
end

---Forget the pinned environment for this project and resolve afresh.
---@param opts pyenv.ActivateOpts?
---@return pyenv.Resolution
function M.reset(opts)
  opts = opts or {}
  local cwd = opts.cwd or vim.fn.getcwd()
  state.clear_override(state.project_root(cwd))
  return M.activate({ cwd = cwd, notify = opts.notify })
end

---The active resolution, or nil if nothing has been activated yet.
---@return pyenv.Resolution?
function M.current()
  return state.current()
end

---A short description of an environment, for statuslines and messages.
---@param resolution pyenv.Resolution?
---@return string
function M.status(resolution)
  resolution = resolution or state.current()
  if not resolution then
    return ""
  end
  if resolution.missing then
    return resolution.version .. " (missing)"
  end
  if resolution.kind == "virtualenv" and resolution.parent then
    return ("%s (%s)"):format(resolution.version, resolution.parent)
  end
  return resolution.version
end

return M
