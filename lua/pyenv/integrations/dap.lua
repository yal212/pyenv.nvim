--- Points nvim-dap at the active interpreter, so debugpy runs inside the
--- environment being debugged rather than whichever Python happens to be first
--- on PATH.
local M = {}

---@class pyenv.DapDeps
---@field require fun(module: string): any injection seam for tests

---Configure debugging for `resolution`.
---
---nvim-dap-python is preferred when present because it also derives the
---`justMyCode`/module launch configurations; plain nvim-dap gets the adapter
---registered directly.
---@param resolution pyenv.Resolution
---@param deps pyenv.DapDeps?
---@return "dap-python"|"dap"|nil which integration was configured
function M.apply(resolution, deps)
  if not resolution.python or resolution.missing then
    return nil
  end

  local require_ = (deps and deps.require) or require

  local ok, dap_python = pcall(require_, "dap-python")
  if ok and type(dap_python) == "table" and type(dap_python.setup) == "function" then
    dap_python.setup(resolution.python)
    return "dap-python"
  end

  local dap_ok, dap = pcall(require_, "dap")
  if dap_ok and type(dap) == "table" and type(dap.adapters) == "table" then
    dap.adapters.python = {
      type = "executable",
      command = resolution.python,
      args = { "-m", "debugpy.adapter" },
    }
    return "dap"
  end

  return nil
end

return M
