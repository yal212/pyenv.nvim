--- The `:Pyenv` command.
---
--- One command with subcommands and completion, rather than a spray of
--- `:PyenvFoo` commands, per the Neovim plugin conventions.
local M = {}

local pyenv = require("pyenv")
local state = require("pyenv.state")

---@param message string
---@param level integer?
local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO)
end

---Names of every installed environment, plus "system".
---@return string[]
local function env_names()
  local names = { "system" }
  for _, env in ipairs(pyenv.list()) do
    names[#names + 1] = env.name
  end
  return names
end

---Human-readable explanation of where the active version came from.
---@param resolution pyenv.Resolution
---@return string
local function explain(resolution)
  local origins = {
    override = "pinned for this project",
    shell = "PYENV_VERSION",
    ["local"] = ".python-version",
    project_venv = "project virtualenv",
    global = "pyenv global",
    system = "system default",
  }
  local reason = origins[resolution.origin] or resolution.origin
  if resolution.origin_file then
    reason = reason .. " at " .. resolution.origin_file
  end
  return reason
end

---@type table<string, { desc: string, run: fun(args: string[]), complete: (fun(): string[])? }>
local subcommands = {}

subcommands.status = {
  desc = "Show the active environment and why it was chosen",
  run = function()
    local resolution = pyenv.current() or pyenv.activate()
    if not resolution then
      return notify("pyenv.nvim: no environment resolved", vim.log.levels.WARN)
    end
    notify(table.concat({
      "pyenv.nvim",
      "  environment : " .. pyenv.status(resolution),
      "  interpreter : " .. (resolution.python or "none"),
      "  chosen by   : " .. explain(resolution),
    }, "\n"))
  end,
}

subcommands.select = {
  desc = "Pick an environment interactively",
  run = function()
    local current = pyenv.current()
    require("pyenv.ui.select").pick(pyenv.list(), current and current.version, function(env)
      if env then
        pyenv.activate({ name = env.name })
      end
    end)
  end,
}

subcommands.activate = {
  desc = "Pin an environment for this project",
  complete = env_names,
  run = function(args)
    if not args[1] then
      return notify("pyenv.nvim: usage: :Pyenv activate <name>", vim.log.levels.ERROR)
    end
    pyenv.activate({ name = args[1] })
  end,
}

subcommands.reset = {
  desc = "Unpin this project and resolve afresh",
  run = function()
    pyenv.reset()
  end,
}

subcommands["local"] = {
  desc = "Write .python-version in the current directory",
  complete = env_names,
  run = function(args)
    local file = vim.fn.getcwd() .. "/.python-version"
    if not args[1] then
      local existing = vim.fn.filereadable(file) == 1 and vim.fn.readfile(file)[1] or nil
      return notify("pyenv.nvim: " .. (existing or "no .python-version here"))
    end
    vim.fn.writefile({ args[1] }, file)
    notify("pyenv.nvim: wrote " .. file)
    -- The pin would otherwise shadow the file we just wrote.
    state.clear_override(state.project_root(vim.fn.getcwd()))
    pyenv.activate()
  end,
}

subcommands.global = {
  desc = "Set the pyenv global version",
  complete = env_names,
  run = function(args)
    local root = pyenv.root()
    if not root then
      return notify("pyenv.nvim: no pyenv root found", vim.log.levels.ERROR)
    end
    local file = root .. "/version"
    if not args[1] then
      local existing = vim.fn.filereadable(file) == 1 and vim.fn.readfile(file)[1] or nil
      return notify("pyenv.nvim: global is " .. (existing or "unset"))
    end
    vim.fn.writefile({ args[1] }, file)
    notify("pyenv.nvim: global set to " .. args[1])
    pyenv.activate()
  end,
}

subcommands.health = {
  desc = "Run the pyenv.nvim health check",
  run = function()
    vim.cmd("checkhealth pyenv")
  end,
}

---@return string[]
function M.names()
  local names = vim.tbl_keys(subcommands)
  table.sort(names)
  return names
end

---@param candidates string[]
---@param lead string
---@return string[]
local function matching(candidates, lead)
  return vim.tbl_filter(function(candidate)
    return vim.startswith(candidate, lead)
  end, candidates)
end

---Completion for `:Pyenv`.
---@param arg_lead string
---@param cmd_line string
---@return string[]
function M.complete(arg_lead, cmd_line)
  local args = vim.split(vim.trim(cmd_line), "%s+")
  -- args[1] is the command itself; a trailing space means the next argument has
  -- been started but is still empty.
  local finished = #args - 1 - (arg_lead == "" and 0 or 1)

  if finished < 1 then
    return matching(M.names(), arg_lead)
  end

  local sub = subcommands[args[2]]
  if sub and sub.complete and finished < 2 then
    return matching(sub.complete(), arg_lead)
  end
  return {}
end

---Dispatch `:Pyenv ...`.
---@param opts { fargs: string[] }
function M.run(opts)
  local args = vim.deepcopy(opts.fargs or {})
  local name = table.remove(args, 1) or "status"

  local sub = subcommands[name]
  if not sub then
    return notify(
      ("pyenv.nvim: unknown subcommand '%s' (try: %s)"):format(name, table.concat(M.names(), ", ")),
      vim.log.levels.ERROR
    )
  end
  sub.run(args)
end

return M
