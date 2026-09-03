--- Points Python language servers at the active interpreter.
---
--- Two mechanisms are needed, because they solve different halves of the
--- problem. `vim.lsp.config()` sits at the highest priority in the config merge
--- chain (`:h lsp-config-merge`), so writing there fixes every *future* client
--- start. Clients that are already running additionally need to be told, either
--- by notification or by restart.
local M = {}

--- How long to wait before acting on a restart request. A `DirChanged` burst
--- fires several activations in quick succession; without this window each one
--- would tear down and rebuild the language server.
M.RESTART_DELAY_MS = 50

--- Where each server wants the interpreter path, and how it copes with being
--- told about a new one.
---
--- pyright and basedpyright do not reliably reload `python.pythonPath` from a
--- `workspace/didChangeConfiguration` notification, so they are restarted.
--- pylsp honours the notification and can be updated in place.
---
--- ruff is deliberately absent: its `interpreter` setting is a VS Code
--- extension option used to locate the ruff binary, not a language server
--- setting, and it plays no part in how ruff lints.
---@type table<string, { key: string[], strategy: "restart"|"notify" }>
M.SERVERS = {
  pyright = { key = { "settings", "python", "pythonPath" }, strategy = "restart" },
  basedpyright = { key = { "settings", "python", "pythonPath" }, strategy = "restart" },
  pylsp = {
    key = { "settings", "pylsp", "plugins", "jedi", "environment" },
    strategy = "notify",
  },
}

---@type table<string, fun(name: string)>
local pending = {}
local scheduled = false

---Build a nested table so that `{"a","b"}` and `v` produce `{ a = { b = v } }`.
---@param keys string[]
---@param value any
---@return table
local function nest(keys, value)
  local root = {}
  local node = root
  for i = 1, #keys - 1 do
    node[keys[i]] = {}
    node = node[keys[i]]
  end
  node[keys[#keys]] = value
  return root
end

---Restart a server.
---
---Neovim has no `vim.lsp.restart()`. Toggling `vim.lsp.enable` is the supported
---route and correctly re-attaches current and future buffers, but it only
---governs configs that were enabled that way; anything started through
---`vim.lsp.start()` directly needs stopping and restarting per buffer.
---@param name string
local function default_restart(name)
  local ok, enabled = pcall(vim.lsp.is_enabled, name)
  if ok and enabled then
    vim.lsp.enable(name, false)
    vim.lsp.enable(name, true)
    return
  end

  for _, client in ipairs(vim.lsp.get_clients({ name = name })) do
    local buffers = vim.tbl_keys(client.attached_buffers or {})
    local config = client.config
    client:stop()
    vim.defer_fn(function()
      for _, buf in ipairs(buffers) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.lsp.start(config, { bufnr = buf })
        end
      end
    end, 100)
  end
end

---@param name string
---@param restart fun(name: string)
local function schedule_restart(name, restart)
  pending[name] = restart
  if scheduled then
    return
  end
  scheduled = true
  vim.defer_fn(function()
    scheduled = false
    local due = pending
    pending = {}
    for server, run in pairs(due) do
      run(server)
    end
  end, M.RESTART_DELAY_MS)
end

---@param resolution pyenv.Resolution
---@return table<string, string>
local function server_env(resolution)
  local cmd_env = {}
  if resolution.kind == "virtualenv" or resolution.kind == "venv" then
    cmd_env.VIRTUAL_ENV = resolution.prefix
  end
  if resolution.prefix then
    cmd_env.PATH = resolution.prefix .. "/bin:" .. (vim.env.PATH or "")
  end
  return cmd_env
end

---@class pyenv.LspDeps
---@field get_clients fun(filter: table): table[]
---@field restart     fun(name: string)

---Point the configured servers at `resolution`.
---@param resolution pyenv.Resolution
---@param opts { servers: string[] }
---@param deps pyenv.LspDeps? injection seam for tests
function M.apply(resolution, opts, deps)
  -- Wiring a server to an interpreter that does not exist is worse than leaving
  -- it alone: it produces a wall of spurious import errors.
  if not resolution.python or resolution.missing then
    return
  end

  deps = deps or {}
  local get_clients = deps.get_clients or vim.lsp.get_clients
  local restart = deps.restart or default_restart
  local cmd_env = server_env(resolution)

  for _, name in ipairs(opts.servers or {}) do
    local adapter = M.SERVERS[name]
    if adapter then
      local config = nest(adapter.key, resolution.python)
      config.cmd_env = cmd_env
      vim.lsp.config(name, config)

      local clients = get_clients({ name = name })
      if #clients > 0 then
        if adapter.strategy == "notify" then
          for _, client in ipairs(clients) do
            client.settings =
              vim.tbl_deep_extend("force", client.settings or {}, config.settings or {})
            client:notify("workspace/didChangeConfiguration", { settings = client.settings })
          end
        else
          schedule_restart(name, restart)
        end
      end
    end
  end
end

---Drop any restart that has been scheduled but not yet run. Used by tests.
function M.reset()
  pending = {}
  scheduled = false
end

return M
