local fx = require("fixtures")

---Unload every pyenv module, which is what `:Lazy reload pyenv.nvim` does, and
---hand back a function that puts the originals back.
---
---Restoring matters: busted runs the whole suite in one Neovim, so leaving the
---fresh instances in `package.loaded` would give every later spec file modules
---that no longer match the ones it required at load time.
---@return fun() restore
local function unload()
  local saved = {}
  for name, module in pairs(package.loaded) do
    if name == "pyenv" or name:match("^pyenv%.") then
      saved[name] = module
    end
  end
  for name in pairs(saved) do
    package.loaded[name] = nil
  end
  return function()
    for name, module in pairs(saved) do
      package.loaded[name] = module
    end
  end
end

---Count exact-match entries in PATH.
---@param dir string
---@return integer
local function path_entries(dir)
  local n = 0
  for entry in vim.gsplit(vim.env.PATH or "", ":", { plain = true }) do
    if entry == dir then
      n = n + 1
    end
  end
  return n
end

describe("pyenv across a plugin reload", function()
  local root, a, b, saved, restore

  ---The options a plugin manager re-applies when it reloads the spec.
  local function configure()
    require("pyenv").setup({
      root = root,
      lsp = { enabled = false },
      dap = { enabled = false },
      cache = { enabled = false },
      notify = false,
    })
  end

  before_each(function()
    saved = {
      PATH = vim.env.PATH,
      PYENV_VERSION = vim.env.PYENV_VERSION,
      VIRTUAL_ENV = vim.env.VIRTUAL_ENV,
    }
    vim.env.PATH = "/usr/bin:/bin"
    vim.env.PYENV_VERSION = nil
    vim.env.VIRTUAL_ENV = nil
    require("pyenv.session").forget()

    root = fx.pyenv_root({ versions = { "3.11.9", "3.12.4" }, global = "3.11.9" })
    a = fx.project({ [".python-version"] = "3.12.4\n" })
    b = fx.project({ [".python-version"] = "3.11.9\n" })

    -- Activate once, so the reloaded instance inherits a process that already
    -- has this plugin's PYENV_VERSION and PATH exported into it.
    configure()
    require("pyenv").activate({ cwd = a })

    restore = unload()
    configure()
  end)

  after_each(function()
    restore()
    require("pyenv.integrations.env").reset()
    vim.env.PATH = saved.PATH
    vim.env.PYENV_VERSION = saved.PYENV_VERSION
    vim.env.VIRTUAL_ENV = saved.VIRTUAL_ENV
    require("pyenv.session").forget()
    require("pyenv.config").reset()
    require("pyenv.state").reset()
    fx.cleanup()
  end)

  it("resolves a new directory afresh rather than from its own exports", function()
    -- The snapshot of the pristine environment is process state, so a reloaded
    -- instance must inherit it. Taking it again reads back the PYENV_VERSION its
    -- predecessor exported, and that value then wins as a "shell" match for the
    -- rest of the session -- pinning every directory to the first one visited.
    local r = require("pyenv").activate({ cwd = b })

    assert.equals("3.11.9", r.version)
    assert.equals("local", r.origin)
    assert.equals("3.11.9", vim.env.PYENV_VERSION)
  end)

  it("does not leave the previous environment's bin directory on PATH", function()
    -- The bin directory this plugin prepended is process state too. A reloaded
    -- instance that cannot see it cannot subtract it, and every switch from then
    -- on leaks another stale directory until the wrong interpreter wins.
    -- Pinned explicitly, because an unpinned activation would resolve to the
    -- same environment and hide the leak behind an unrelated code path.
    require("pyenv").activate({ cwd = b, name = "3.11.9" })

    assert.equals(1, path_entries(root .. "/versions/3.11.9/bin"))
    assert.equals(0, path_entries(root .. "/versions/3.12.4/bin"))
    assert.equals("/usr/bin:/bin", vim.env.PATH:sub(-#"/usr/bin:/bin"))
  end)
end)
