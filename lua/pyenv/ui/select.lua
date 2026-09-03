--- Environment picker built on `vim.ui.select`.
---
--- Deliberately dependency-free: `vim.ui.select` already routes to whichever
--- picker the user has configured (telescope, snacks, fzf-lua, dressing, or the
--- built-in prompt), so bundling one would only take that choice away.
local M = {}

---@param env pyenv.Env
---@param active string?
---@return string
local function label(env, active)
  local marker = (env.name == active) and "● " or "  "
  local detail = env.kind == "virtualenv"
      and ("virtualenv" .. (env.parent and (" of " .. env.parent) or ""))
    or "version"
  return ("%s%-24s %s"):format(marker, env.name, detail)
end

---Prompt for an environment.
---@param items pyenv.Env[]
---@param active string? name of the currently active environment
---@param on_choice fun(env: pyenv.Env?)
function M.pick(items, active, on_choice)
  if #items == 0 then
    vim.notify("pyenv.nvim: no environments installed", vim.log.levels.WARN)
    return
  end

  vim.ui.select(items, {
    prompt = "Python environment",
    format_item = function(env)
      return label(env, active)
    end,
  }, on_choice)
end

return M
