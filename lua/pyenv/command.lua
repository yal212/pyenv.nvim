--- The `:Pyenv` command.
---
--- One command with subcommands and completion, rather than a spray of
--- `:PyenvFoo` commands, per the Neovim plugin conventions.
local M = {}

local cli = require("pyenv.cli")
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

---Names of installed versions only (not virtualenvs), for `virtualenv`.
---@return string[]
local function version_names()
  local names = {}
  for _, env in ipairs(pyenv.list()) do
    if env.kind == "version" then
      names[#names + 1] = env.name
    end
  end
  return names
end

--- Versions offered by `pyenv install --list`, kept for the session. The fetch
--- takes about a second, far too slow to run inside a <Tab> handler, so
--- completion starts one in the background and reads this on a later keystroke.
---@type string[]
local available = {}

--- Callbacks waiting on the fetch currently in flight, or nil when there is
--- none. Completion primes the cache in the background, so a burst of <Tab>
--- presses has to join the one fetch rather than start a `pyenv` apiece.
---@type fun(versions: string[])[]?
local waiting = nil

---Fill `available`, then hand it to `callback` if there is one. Called without
---a callback purely to prime the cache.
---@param callback fun(versions: string[])?
local function fetch_available(callback)
  if #available > 0 then
    return callback and callback(available)
  end
  if waiting then
    if callback then
      waiting[#waiting + 1] = callback
    end
    return
  end

  local lines = {}
  -- Assigned before the spawn so that neither the exit callback nor the
  -- nil-handle path below can see a queue that is only half set up.
  waiting = callback and { callback } or {}

  local handle = cli.run({ "install", "--list" }, {
    on_output = function(line)
      lines[#lines + 1] = line
    end,
    on_exit = function(code)
      local queued = waiting or {}
      waiting = nil
      if code ~= 0 then
        return notify("pyenv.nvim: could not list available versions", vim.log.levels.ERROR)
      end
      available = cli.parse_available(lines)
      for _, ready in ipairs(queued) do
        ready(available)
      end
    end,
  })

  -- cli.run has already reported the missing binary and given up without
  -- spawning anything, so neither callback will ever fire. Announcing the fetch
  -- before this point left "fetching..." standing as the last thing on screen
  -- with nothing able to resolve it -- the same nil return `managed` handles by
  -- taking its progress window back down.
  if not handle then
    waiting = nil
    return
  end
  notify("pyenv.nvim: fetching available versions...")
end

---Run a long-running pyenv command with its output in a floating window.
---@param title string
---@param args string[]
---@param on_success fun()?
local function managed(title, args, on_success)
  local handle
  local progress = require("pyenv.ui.progress").open(title, function()
    if handle then
      pcall(function()
        handle:kill(15)
      end)
    end
  end)

  handle = cli.run(args, {
    on_output = progress.append,
    on_exit = function(code)
      progress.finish(code)
      if code == 0 and on_success then
        on_success()
      end
    end,
  })

  -- cli.run already explained why; just take the window back down.
  if not handle then
    progress.close()
  end
end

subcommands.install = {
  desc = "Install a Python version",
  complete = function()
    if #available == 0 then
      -- Prime in the background: this keystroke gets nothing, the next one
      -- finds the list ready. Fetching inline would stall <Tab> for a second,
      -- and nothing else populates the cache until `:Pyenv install` is run bare.
      fetch_available()
      return {}
    end
    -- Offered only now that there is something to refresh. As the sole
    -- candidate it would make the first <Tab> complete straight to `--refresh`,
    -- which is the opposite of what that keystroke was asking for.
    return vim.list_extend({ "--refresh" }, available)
  end,
  run = function(args)
    local function install(version)
      -- -s: succeed quietly if it is already installed.
      managed("pyenv install " .. version, { "install", "-s", version }, function()
        notify("pyenv.nvim: installed " .. version)
        pyenv.activate()
      end)
    end

    -- The cache lasts the session and never expires on its own, so a Python
    -- released since Neovim started would otherwise stay out of reach.
    if args[1] == "--refresh" then
      available = {}
      table.remove(args, 1)
    end

    if args[1] then
      return install(args[1])
    end
    fetch_available(function(versions)
      vim.ui.select(versions, { prompt = "Install Python version" }, function(choice)
        if choice then
          install(choice)
        end
      end)
    end)
  end,
}

subcommands.uninstall = {
  desc = "Remove an installed version or virtualenv",
  complete = env_names,
  run = function(args)
    if not args[1] then
      return notify("pyenv.nvim: usage: :Pyenv uninstall <name>", vim.log.levels.ERROR)
    end
    -- Destructive and not undoable, so always confirm, defaulting to No.
    if vim.fn.confirm(("Remove %s?"):format(args[1]), "&Yes\n&No", 2, "Question") ~= 1 then
      return
    end
    managed("pyenv uninstall " .. args[1], { "uninstall", "-f", args[1] }, function()
      notify("pyenv.nvim: removed " .. args[1])
      pyenv.activate()
    end)
  end,
}

subcommands.virtualenv = {
  desc = "Create a pyenv virtualenv",
  complete = version_names,
  run = function(args)
    if #args < 2 then
      return notify("pyenv.nvim: usage: :Pyenv virtualenv <version> <name>", vim.log.levels.ERROR)
    end
    managed(("pyenv virtualenv %s %s"):format(args[1], args[2]), {
      "virtualenv",
      args[1],
      args[2],
    }, function()
      notify("pyenv.nvim: created " .. args[2])
      pyenv.activate({ name = args[2] })
    end)
  end,
}

subcommands.rehash = {
  desc = "Regenerate pyenv shims",
  run = function()
    -- Fast and silent; a progress window would be noise.
    cli.run({ "rehash" }, {
      on_exit = function(code)
        notify(
          code == 0 and "pyenv.nvim: shims rehashed" or "pyenv.nvim: rehash failed",
          code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR
        )
      end,
    })
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
