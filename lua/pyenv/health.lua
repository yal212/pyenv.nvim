--- `:checkhealth pyenv`
---
--- The point of this report is to answer one question that is otherwise very
--- hard to answer from inside Neovim: *which* Python is active, *why* it was
--- chosen, and whether the language server actually received it.
local M = {}

local config = require("pyenv.config")
local lsp = require("pyenv.integrations.lsp")
local pyenv = require("pyenv")
local root_mod = require("pyenv.root")

---@param reporter table
local function check_neovim(reporter)
  if vim.fn.has("nvim-0.11") == 1 then
    reporter.ok("Neovim " .. tostring(vim.version()))
  else
    reporter.error("Neovim 0.11 or newer is required (vim.lsp.config / vim.lsp.enable)")
  end
end

---@param reporter table
---@return string? root
local function check_pyenv(reporter)
  local cfg = config.get()
  local root = pyenv.root()

  if not root then
    reporter.warn("no pyenv root found", {
      "Set `root` in setup(), export PYENV_ROOT, or install pyenv to ~/.pyenv.",
      "Environment switching still works for project .venv directories.",
    })
    return nil
  end

  local source = cfg.root and "configured" or (vim.env.PYENV_ROOT and "PYENV_ROOT" or "default")
  if vim.fn.isdirectory(root) == 1 then
    reporter.ok(("pyenv root: %s (%s)"):format(root, source))
  else
    reporter.error(("pyenv root does not exist: %s (%s)"):format(root, source))
    return root
  end

  local binary = root_mod.binary(root)
  if binary then
    local version = vim.system({ binary, "--version" }, { text = true }):wait(3000)
    local text = vim.trim((version.stdout or "") .. (version.stderr or ""))
    reporter.ok(("pyenv binary: %s%s"):format(binary, text ~= "" and (" (" .. text .. ")") or ""))
  else
    reporter.warn("pyenv executable not found", {
      "Listing and switching still work; they read $PYENV_ROOT directly.",
      "Installing and removing versions needs the pyenv binary on PATH.",
    })
  end

  local shims = root .. "/shims"
  local on_path = false
  for dir in vim.gsplit(vim.env.PATH or "", ":", { plain = true }) do
    on_path = on_path or vim.fs.normalize(dir) == shims
  end
  if on_path then
    reporter.ok("pyenv shims are on PATH")
  else
    reporter.warn("pyenv shims are not on PATH", {
      "pyenv is probably not initialised in your shell.",
      'Add `eval "$(pyenv init -)"` to your shell profile.',
    })
  end

  return root
end

---@param reporter table
local function check_conflicts(reporter)
  if vim.fn.executable("asdf") == 1 then
    reporter.warn("asdf is installed alongside pyenv", {
      "If asdf's python plugin is enabled, both tools manage shims and the one",
      "earlier on PATH wins. Expect confusing interpreter choices.",
    })
  end

  for _, other in ipairs({ "venv-selector", "swenv" }) do
    if package.loaded[other] or vim.api.nvim_get_runtime_file("lua/" .. other, false)[1] then
      reporter.warn(("%s is also installed"):format(other), {
        "Two plugins setting pythonPath will fight over the language server.",
        "Disable one of them.",
      })
    end
  end
end

---@param reporter table
---@param root string?
local function check_active(reporter, root)
  local resolution = pyenv.current() or pyenv.resolve()
  if not resolution then
    reporter.warn("no environment resolved")
    return
  end

  reporter.info(("active environment: %s"):format(pyenv.status(resolution)))
  reporter.info(
    ("chosen by: %s%s"):format(
      resolution.origin,
      resolution.origin_file and (" -> " .. resolution.origin_file) or ""
    )
  )

  if resolution.missing then
    reporter.error(("%s is not installed"):format(resolution.version), {
      ("Install it with `:Pyenv install %s`."):format(resolution.version),
    })
  elseif not resolution.python then
    reporter.error("no interpreter resolved")
  elseif vim.fn.executable(resolution.python) == 1 then
    reporter.ok("interpreter: " .. resolution.python)
  else
    reporter.error("interpreter is not executable: " .. resolution.python)
  end

  -- Cross-check against pyenv itself. Resolution is reimplemented here rather
  -- than shelled out for speed, so a divergence must surface as a warning
  -- instead of as silent wrongness.
  local binary = root and root_mod.binary(root)
  if binary and resolution.origin ~= "override" and resolution.origin ~= "project_venv" then
    -- The root has to go with it. Without it pyenv answers about ~/.pyenv, and
    -- a check meant to catch a real divergence instead invents one -- "pyenv
    -- reports 'system' but this plugin resolved '3.12.9'" -- or, when the
    -- version is simply not installed over there, exits non-zero and is skipped.
    local proc = vim.system({ binary, "version-name" }, {
      text = true,
      env = { PYENV_ROOT = root },
    })
    local out = proc:wait(3000)
    local reported = vim.trim(out.stdout or "")
    if out.code == 0 and reported ~= "" and reported ~= resolution.version then
      reporter.warn(
        ("pyenv reports '%s' but this plugin resolved '%s'"):format(reported, resolution.version),
        { "Please report this as a bug: the resolution rules have diverged." }
      )
    end
  end
end

---@param reporter table
local function check_lsp(reporter)
  local cfg = config.get()
  if not cfg.lsp.enabled then
    reporter.info("LSP integration is disabled")
    return
  end

  local resolution = pyenv.current()
  local expected = resolution and resolution.python
  local found = false

  for _, name in ipairs(cfg.lsp.servers) do
    for _, client in ipairs(vim.lsp.get_clients({ name = name })) do
      found = true
      local actual = lsp.client_interpreter(client, name)
      if not actual then
        reporter.warn(("%s is running but has no interpreter configured"):format(name))
      elseif expected and actual ~= expected then
        reporter.error(("%s is using %s, not %s"):format(name, actual, expected), {
          "Something else is setting the interpreter. A `before_init` hook in",
          "your LSP config is the usual cause.",
        })
      else
        reporter.ok(("%s is using %s"):format(name, actual))
      end
    end
  end

  if not found then
    reporter.info("no Python language server is running in this session")
  end
end

---Run the health check.
---@param reporter table? injection seam for tests; defaults to `vim.health`
function M.check(reporter)
  reporter = reporter or vim.health
  reporter.start("pyenv.nvim")

  check_neovim(reporter)
  local root = check_pyenv(reporter)
  check_conflicts(reporter)
  check_active(reporter, root)
  check_lsp(reporter)
end

return M
