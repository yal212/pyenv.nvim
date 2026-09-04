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
---@field system fun(cmd: string[], opts: table, on_exit: fun(obj: table)): table
---@field binary string?

---@class pyenv.CliOpts
---@field on_output fun(line: string)?  called per line of combined output
---@field on_exit   fun(code: integer)? called once the process finishes

---Locate the pyenv executable, or nil.
---@return string?
function M.binary()
  local cfg = config.get()
  return root_mod.binary(root_mod.find({ configured = cfg.root, env = vim.env.PYENV_ROOT }))
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

  local binary = deps.binary or M.binary()
  if not binary then
    vim.notify(
      "pyenv.nvim: the pyenv executable is required for this command.\n"
        .. "Run :checkhealth pyenv for details.",
      vim.log.levels.ERROR
    )
    return nil
  end

  local system = deps.system or vim.system

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

  return system(
    vim.list_extend({ binary }, args),
    { text = true, stdout = make_emit(), stderr = make_emit() },
    function(obj)
      if opts.on_exit then
        vim.schedule(function()
          opts.on_exit(obj.code)
        end)
      end
    end
  )
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
