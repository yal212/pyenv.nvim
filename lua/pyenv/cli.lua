--- Async wrapper around the `pyenv` executable.
---
--- Only state-changing operations go through here. Everything the plugin reads
--- comes from the filesystem instead, so listing and switching keep working
--- when pyenv is not on Neovim's PATH; only installing and removing genuinely
--- need the binary.
local M = {}

local config = require("pyenv.config")
local root_mod = require("pyenv.root")

---@class pyenv.CliDeps
---@field system fun(cmd: string[], opts: table, on_exit: fun(obj: table)): table|false
---@field binary string|false? `false` means "no pyenv here", as against nil for "not injected"

---@class pyenv.CliOpts
---@field on_output fun(line: string)?  called per line of combined output
---@field on_exit   fun(code: integer)? called once the process finishes

---The root in use and the executable that goes with it, found together so that
---the root deciding *which* binary to run is also the one handed to it.
---@return string? root, string? binary
local function locate()
  local cfg = config.get()
  local root = root_mod.find({ configured = cfg.root, env = vim.env.PYENV_ROOT })
  return root, root_mod.binary(root)
end

---Locate the pyenv executable, or nil.
---@return string?
function M.binary()
  local _, binary = locate()
  return binary
end

---Split a stream chunk into whole lines. `vim.system` hands over arbitrary
---chunks, not lines, so partial lines must be buffered across calls.
---@param on_line fun(line: string)
---@return fun(err: string?, data: string?)
local function line_reader(on_line)
  local buffer = ""
  return function(_, data)
    if not data then
      if buffer ~= "" then
        on_line(buffer)
        buffer = ""
      end
      return
    end
    buffer = buffer .. data
    while true do
      local newline = buffer:find("\n")
      if not newline then
        break
      end
      on_line(buffer:sub(1, newline - 1))
      buffer = buffer:sub(newline + 1)
    end
  end
end

---Run `pyenv <args...>` asynchronously.
---@param args string[]
---@param opts pyenv.CliOpts?
---@param deps pyenv.CliDeps? injection seam for tests
---@return table? handle  nil when pyenv is unavailable
function M.run(args, opts, deps)
  opts = opts or {}
  deps = deps or {}

  local root, located = locate()
  -- `or` is wrong for an injection seam: the specs pass `false` to mean "this
  -- machine has no pyenv", and `false or located` hands back the real lookup --
  -- so the branch below went untested everywhere and, on a machine that does
  -- have pyenv, spawned it for real. Absent has to be distinguishable from
  -- not injected.
  local binary = deps.binary
  if binary == nil then
    binary = located
  end
  if not binary then
    vim.notify(
      "pyenv.nvim: the pyenv executable is required for this command.\n"
        .. "Run :checkhealth pyenv for details.",
      vim.log.levels.ERROR
    )
    return nil
  end

  local system = deps.system
  if system == nil then
    system = vim.system
  end

  -- One reader per stream, sharing nothing. libuv delivers the two pipes
  -- independently, so a single buffer would splice a whole line from one into
  -- the middle of a half-received line from the other -- which is precisely
  -- what `pyenv install` does for minutes on end.
  local function make_emit()
    if not opts.on_output then
      return nil
    end
    return line_reader(function(line)
      vim.schedule(function()
        opts.on_output(line)
      end)
    end)
  end

  return system(vim.list_extend({ binary }, args), {
    text = true,
    -- pyenv reads its root from the environment, or falls back to ~/.pyenv --
    -- never from the path of the binary that was invoked. A root this plugin
    -- knows about has to be handed over explicitly, or a configured root ends
    -- up reading one tree and writing to another. Merged with the inherited
    -- environment, since `clear_env` is not set.
    env = root and { PYENV_ROOT = root } or nil,
    -- In its own process group, so that `stop` below can take down everything
    -- the command spawns rather than only the command itself.
    detach = true,
    stdout = make_emit(),
    stderr = make_emit(),
  }, function(obj)
    if opts.on_exit then
      -- A process killed by a signal reports code 0 with the signal beside it,
      -- so passing the code straight through would present a cancelled install
      -- as a completed one -- "installed 3.12.9" for a build that was stopped
      -- half way. 128 + signal is what a shell reports for the same thing.
      local code = obj.signal and obj.signal ~= 0 and (128 + obj.signal) or obj.code
      vim.schedule(function()
        opts.on_exit(code)
      end)
    end
  end)
end

---Stop a running command, and everything it spawned with it.
---
---`run` starts children detached, so each leads its own process group and a
---negative pid takes the whole tree down. That is the entire point: `pyenv
---install` is a bash script that spawns python-build, which spawns make, which
---spawns a compiler. Signalling the script alone leaves the build running --
---and finishing, and installing the version that was just cancelled.
---@param handle table?  the handle `run` returned
---@param deps { kill: fun(pid: integer, signal: string|integer) }? test seam
---@return boolean stopped
function M.stop(handle, deps)
  local kill = (deps or {}).kill or vim.uv.kill
  local pid = handle and handle.pid

  -- A negative pid names a process group, and group 0 is the caller's own:
  -- `kill(-0, ...)` would take Neovim down along with the build. Anything that
  -- is not a real child pid is not worth the risk.
  if type(pid) ~= "number" or pid <= 1 then
    return false
  end

  if pcall(kill, -pid, "sigterm") then
    return true
  end

  -- The group is the point, but stopping the child alone beats stopping nothing.
  return pcall(function()
    handle:kill(15)
  end)
end

---Parse the output of `pyenv install --list`.
---@param lines string[]
---@return string[]
function M.parse_available(lines)
  local versions = {}
  for _, line in ipairs(lines) do
    local trimmed = vim.trim(line)
    -- The first line is the "Available versions:" header.
    if trimmed ~= "" and not trimmed:match("^Available versions:") then
      versions[#versions + 1] = trimmed
    end
  end
  return versions
end

return M
