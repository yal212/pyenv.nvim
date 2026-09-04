local fx = require("fixtures")
local config = require("pyenv.config")
local pyenv = require("pyenv")
local session = require("pyenv.session")
local state = require("pyenv.state")
local statusline = require("pyenv.statusline")

describe("pyenv.statusline", function()
  local root, saved

  before_each(function()
    saved = { PATH = vim.env.PATH, PYENV_VERSION = vim.env.PYENV_VERSION }
    vim.env.PATH = "/usr/bin:/bin"
    vim.env.PYENV_VERSION = nil
    -- The environment snapshot is taken once per process and survives a reload,
    -- so drop the previous case's before setup() takes this one's.
    session.forget()

    root = fx.pyenv_root({
      versions = { "3.12.4" },
      virtualenvs = { ["3.12.4"] = { "proj-env" } },
    })
    pyenv.setup({
      root = root,
      lsp = { enabled = false },
      dap = { enabled = false },
      cache = { enabled = false },
      notify = false,
    })
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

  it("is empty when nothing is active, so the section disappears", function()
    state.set_current(nil)
    assert.equals("", statusline.status())
  end)

  it("shows the active environment", function()
    pyenv.activate({ cwd = fx.project({ [".python-version"] = "proj-env\n" }) })
    assert.equals("proj-env (3.12.4)", statusline.status())
  end)

  it("adds a prefix when asked", function()
    pyenv.activate({ cwd = fx.project({ [".python-version"] = "3.12.4\n" }) })
    assert.equals("py: 3.12.4", statusline.status({ prefix = "py:" }))
  end)

  it("does not add a prefix to an empty status", function()
    state.set_current(nil)
    assert.equals("", statusline.status({ prefix = "py:" }))
  end)

  describe("lualine component", function()
    it("renders the status", function()
      pyenv.activate({ cwd = fx.project({ [".python-version"] = "3.12.4\n" }) })
      local component = statusline.lualine()
      assert.equals("3.12.4", component[1]())
      assert.is_true(component.cond())
    end)

    it("hides itself when nothing is active", function()
      state.set_current(nil)
      assert.is_false(statusline.lualine().cond())
    end)
  end)
end)
