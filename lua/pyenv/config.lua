--- User configuration: defaults, validation, and merging.
---
--- `setup()` is optional. The plugin auto-initialises with these defaults, so
--- calling it is only necessary to change something.
local M = {}

local resolve = require("pyenv.resolve")

---@class pyenv.Config
---@field root              string?  override `$PYENV_ROOT`
---@field auto_activate     boolean  re-resolve on VimEnter and DirChanged
---@field resolution_order  string[] priority order of resolution steps
---@field lsp               pyenv.Config.Lsp
---@field dap               pyenv.Config.Dap
---@field terminal          pyenv.Config.Terminal
---@field python3_host_prog boolean  point `g:python3_host_prog` at the active env
---@field notify            "all"|"changes"|"errors"|false
---@field cache             pyenv.Config.Cache

---@class pyenv.Config.Lsp
---@field enabled boolean
---@field servers string[]
---@field strategy "notify"|"restart" how a *running* client is told about a new interpreter

---@class pyenv.Config.Dap
---@field enabled boolean

---@class pyenv.Config.Terminal
---@field set_path        boolean
---@field set_virtual_env boolean

---@class pyenv.Config.Cache
---@field enabled boolean
---@field path    string?

---@type pyenv.Config
M.defaults = {
  auto_activate = true,
  resolution_order = resolve.DEFAULT_ORDER,
  lsp = {
    enabled = true,
    servers = { "pyright", "basedpyright", "pylsp" },
    -- A notification updates a running server in place; a restart makes it
    -- re-index the whole project. See `pyenv.integrations.lsp` for what the
    -- restart buys and when it is worth asking for.
    strategy = "notify",
  },
  dap = { enabled = true },
  terminal = {
    set_path = true,
    set_virtual_env = true,
  },
  -- Off by default: pointing Neovim's Python host at an environment without
  -- pynvim installed breaks every remote plugin.
  python3_host_prog = false,
  notify = "changes",
  cache = { enabled = true },
}

--- Accepted options and their types. This is separate from `defaults` because
--- options that default to nil (`root`, `cache.path`) cannot be described by a
--- Lua table literal, yet still need to be recognised and type-checked.
local SCHEMA = {
  root = "string",
  auto_activate = "boolean",
  resolution_order = "table",
  lsp = {
    enabled = "boolean",
    servers = "table",
    strategy = "string",
  },
  dap = { enabled = "boolean" },
  terminal = {
    set_path = "boolean",
    set_virtual_env = "boolean",
  },
  python3_host_prog = "boolean",
  notify = "string|boolean",
  cache = {
    enabled = "boolean",
    path = "string",
  },
}

--- Accepted `lsp.strategy` values. Checked by value and not just by type: a
--- typo that fell through to the default would leave a running server pointed
--- at the old interpreter without saying so.
local STRATEGIES = { notify = true, restart = true }

---@param message string
local function fail(message)
  -- level 0: no "file:line:" prefix, so the message reads as plain user-facing text.
  error("pyenv.nvim: " .. message, 0)
end

---@param opts table
---@param schema table
---@param prefix string
local function validate(opts, schema, prefix)
  for key, value in pairs(opts) do
    local expected = schema[key]
    local path = prefix .. tostring(key)

    if expected == nil then
      fail(("unknown option '%s'"):format(path))
    elseif type(expected) == "table" then
      if type(value) ~= "table" then
        fail(("option '%s' expects table, got %s"):format(path, type(value)))
      end
      validate(value, expected, path .. ".")
    else
      local ok = false
      for want in vim.gsplit(expected, "|", { plain = true }) do
        ok = ok or type(value) == want
      end
      if not ok then
        fail(("option '%s' expects %s, got %s"):format(path, expected, type(value)))
      end
    end
  end
end

---Deep-merge, but replace list-like tables wholesale. Merging them by index
---would make it impossible to shorten a list such as `lsp.servers`.
---@param base table
---@param override table
---@return table
local function merge(base, override)
  local out = vim.deepcopy(base)
  for key, value in pairs(override) do
    if type(value) == "table" and type(out[key]) == "table" and not vim.islist(value) then
      out[key] = merge(out[key], value)
    else
      out[key] = vim.deepcopy(value)
    end
  end
  return out
end

---@type pyenv.Config?
local current = nil

---Validate and apply user options.
---@param opts table?
---@return pyenv.Config
function M.setup(opts)
  opts = opts or {}
  if type(opts) ~= "table" then
    fail(("setup() expects a table, got %s"):format(type(opts)))
  end
  validate(opts, SCHEMA, "")

  local valid_steps = {}
  for _, step in ipairs(resolve.DEFAULT_ORDER) do
    valid_steps[step] = true
  end
  for _, step in ipairs(opts.resolution_order or {}) do
    if not valid_steps[step] then
      fail(("unknown resolution step '%s'"):format(tostring(step)))
    end
  end

  local strategy = opts.lsp and opts.lsp.strategy
  if strategy ~= nil and not STRATEGIES[strategy] then
    fail(("unknown lsp strategy '%s'"):format(tostring(strategy)))
  end

  current = merge(M.defaults, opts)
  return current
end

---The active configuration, defaults included when `setup()` was never called.
---@return pyenv.Config
function M.get()
  if not current then
    current = vim.deepcopy(M.defaults)
  end
  return current
end

---Discard user options. Used by tests.
function M.reset()
  current = nil
end

return M
