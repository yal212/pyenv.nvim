local config = require("pyenv.config")
local fx = require("fixtures")
local health = require("pyenv.health")
local pyenv = require("pyenv")
local session = require("pyenv.session")
local state = require("pyenv.state")

---Collects what the health check reports, in place of `vim.health`.
local function recorder()
  local entries = {}
  local function record(level)
    return function(msg, advice)
      table.insert(entries, { level = level, msg = msg, advice = advice })
    end
  end
  return {
    entries = entries,
    start = record("start"),
    ok = record("ok"),
    info = record("info"),
    warn = record("warn"),
    error = record("error"),
  }
end

---@return table? first entry whose message matches `pattern`
local function find(report, pattern)
  for _, entry in ipairs(report.entries) do
    if entry.msg:match(pattern) then
      return entry
    end
  end
  return nil
end

describe("pyenv.health", function()
  local root, saved

  local function configure(extra)
    pyenv.setup(vim.tbl_deep_extend("force", {
      root = root,
      lsp = { enabled = false },
      dap = { enabled = false },
      cache = { enabled = false },
      notify = false,
    }, extra or {}))
  end

  before_each(function()
    saved = {
      PATH = vim.env.PATH,
      PYENV_VERSION = vim.env.PYENV_VERSION,
      PYENV_ROOT = vim.env.PYENV_ROOT,
    }
    vim.env.PATH = "/usr/bin:/bin"
    vim.env.PYENV_VERSION = nil
    vim.env.PYENV_ROOT = nil
    -- The environment snapshot is taken once per process and survives a reload,
    -- so drop the previous case's before setup() takes this one's.
    session.forget()

    root = fx.pyenv_root({ versions = { "3.11.9", "3.12.4" }, global = "3.11.9" })
    configure()
  end)

  after_each(function()
    require("pyenv.integrations.env").reset()
    config.reset()
    state.reset()
    for k, v in pairs(saved) do
      vim.env[k] = v
    end
    fx.cleanup()
  end)

  local function run()
    local report = recorder()
    health.check(report)
    return report
  end

  it("reports the pyenv root and how it was found", function()
    local entry = find(run(), "pyenv root: " .. vim.pesc(root))
    assert.is_not_nil(entry)
    assert.equals("ok", entry.level)
    assert.is_truthy(entry.msg:match("configured"))
  end)

  it("errors when the configured root does not exist", function()
    configure({ root = "/nowhere/pyenv" })
    local entry = find(run(), "pyenv root does not exist")
    assert.equals("error", entry.level)
  end)

  it("warns when the shims directory is not on PATH", function()
    local entry = find(run(), "shims are not on PATH")
    assert.equals("warn", entry.level)
    assert.is_truthy(table.concat(entry.advice, " "):match("pyenv init"))
  end)

  it("confirms the shims directory when it is on PATH", function()
    vim.env.PATH = root .. "/shims:/usr/bin:/bin"
    assert.equals("ok", find(run(), "shims are on PATH").level)
  end)

  it("warns when the pyenv binary is missing but says listing still works", function()
    local entry = find(run(), "pyenv executable not found")
    assert.equals("warn", entry.level)
    assert.is_truthy(table.concat(entry.advice, " "):match("still work"))
  end)

  it("names the active environment and the file that chose it", function()
    local proj = fx.project({ [".python-version"] = "3.12.4\n" })
    pyenv.activate({ cwd = proj })

    local report = run()
    assert.is_not_nil(find(report, "active environment: 3%.12%.4"))
    assert.is_not_nil(find(report, "chosen by: local %-> " .. vim.pesc(proj)))
  end)

  it("confirms an interpreter that exists", function()
    pyenv.activate({ cwd = fx.project({ [".python-version"] = "3.12.4\n" }) })
    local entry = find(run(), "interpreter: ")
    assert.equals("ok", entry.level)
    assert.is_truthy(entry.msg:match("3%.12%.4/bin/python"))
  end)

  it("errors on a version that is not installed, and says how to fix it", function()
    pyenv.activate({ cwd = fx.project({ [".python-version"] = "3.13.0\n" }) })

    local entry = find(run(), "3%.13%.0 is not installed")
    assert.equals("error", entry.level)
    assert.is_truthy(table.concat(entry.advice, " "):match("Pyenv install 3%.13%.0"))
  end)

  it("reports when no Python language server is running", function()
    configure({ lsp = { enabled = true } })
    assert.is_not_nil(find(run(), "no Python language server is running"))
  end)

  it("says so when the LSP integration is switched off", function()
    assert.is_not_nil(find(run(), "LSP integration is disabled"))
  end)

  it("warns when no pyenv root can be found at all", function()
    config.reset()
    pyenv.setup({
      root = nil,
      lsp = { enabled = false },
      dap = { enabled = false },
      cache = { enabled = false },
      notify = false,
    })
    -- Point HOME somewhere without a .pyenv so discovery genuinely fails.
    local home = vim.env.HOME
    vim.env.HOME = fx.tmpdir("no-pyenv-home")

    local entry = find(run(), "no pyenv root found")
    vim.env.HOME = home

    assert.equals("warn", entry.level)
    assert.is_truthy(table.concat(entry.advice, " "):match("%.venv"))
  end)
end)
