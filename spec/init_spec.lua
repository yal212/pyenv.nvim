local fx = require("fixtures")
local config = require("pyenv.config")
local pyenv = require("pyenv")
local state = require("pyenv.state")

describe("pyenv (public API)", function()
  local root, saved

  local function configure(extra)
    pyenv.setup(vim.tbl_deep_extend("force", {
      root = root,
      lsp = { enabled = false },
      dap = { enabled = false },
      cache = { enabled = false },
      -- Silent unless a test opts in; otherwise every activation would call the
      -- real vim.notify and scribble over the test output.
      notify = false,
    }, extra or {}))
  end

  before_each(function()
    saved = {
      PATH = vim.env.PATH,
      PYENV_VERSION = vim.env.PYENV_VERSION,
      VIRTUAL_ENV = vim.env.VIRTUAL_ENV,
      PYENV_ROOT = vim.env.PYENV_ROOT,
    }
    vim.env.PATH = "/usr/bin:/bin"
    vim.env.PYENV_VERSION = nil
    vim.env.VIRTUAL_ENV = nil
    vim.env.PYENV_ROOT = nil

    root = fx.pyenv_root({
      versions = { "3.11.9", "3.12.4" },
      virtualenvs = { ["3.12.4"] = { "proj-env" } },
      global = "3.11.9",
    })
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

  describe("activate", function()
    it("resolves and records the active environment", function()
      local r = pyenv.activate({ cwd = fx.project({ [".python-version"] = "3.12.4\n" }) })
      assert.equals("3.12.4", r.version)
      assert.equals("3.12.4", pyenv.current().version)
    end)

    it("exports the interpreter to the editor environment", function()
      local proj = fx.project({ [".python-version"] = "proj-env\n" })
      pyenv.activate({ cwd = proj })

      assert.equals("proj-env", vim.env.PYENV_VERSION)
      assert.equals(root .. "/versions/3.12.4/envs/proj-env", vim.env.VIRTUAL_ENV)
      assert.equals(root .. "/versions/3.12.4/envs/proj-env/bin", vim.split(vim.env.PATH, ":")[1])
    end)

    it("does not let its own exports pin later resolutions", function()
      -- Regression guard. Activating exports PYENV_VERSION; if resolution read
      -- the live environment back, that export would win as a "shell" match and
      -- every subsequent directory would keep the first project's version.
      local a = fx.project({ [".python-version"] = "3.12.4\n" })
      local b = fx.project({ [".python-version"] = "3.11.9\n" })

      assert.equals("3.12.4", pyenv.activate({ cwd = a }).version)
      assert.equals("3.11.9", pyenv.activate({ cwd = b }).version)
    end)

    it("does not let an exported VIRTUAL_ENV win as a project venv", function()
      local a = fx.project({ [".python-version"] = "proj-env\n" })
      pyenv.activate({ cwd = a })
      assert.equals("proj-env", pyenv.current().version)

      -- An unmarked directory must fall through to the global version, not to
      -- the VIRTUAL_ENV the previous activation exported.
      local r = pyenv.activate({ cwd = fx.tmpdir("unmarked") })
      assert.equals("3.11.9", r.version)
      assert.equals("global", r.origin)
    end)

    it("pins an environment for the project when given a name", function()
      local proj = fx.project({ [".python-version"] = "3.11.9\n" })
      assert.equals("3.12.4", pyenv.activate({ cwd = proj, name = "3.12.4" }).version)
      -- and it sticks on a later plain activation
      assert.equals("3.12.4", pyenv.activate({ cwd = proj }).version)
      assert.equals("override", pyenv.current().origin)
    end)

    it("honours PYENV_ROOT from the environment", function()
      config.reset()
      vim.env.PYENV_ROOT = root
      pyenv.setup({
        lsp = { enabled = false },
        dap = { enabled = false },
        cache = { enabled = false },
        notify = false,
      })

      assert.equals(root, pyenv.root())
      assert.equals(
        "3.12.4",
        pyenv.activate({ cwd = fx.project({ [".python-version"] = "3.12.4\n" }) }).version
      )
    end)
  end)

  describe("reset", function()
    it("drops the pinned environment and resolves afresh", function()
      local proj = fx.project({ [".python-version"] = "3.11.9\n" })
      pyenv.activate({ cwd = proj, name = "3.12.4" })
      assert.equals("3.12.4", pyenv.current().version)

      assert.equals("3.11.9", pyenv.reset({ cwd = proj }).version)
      assert.equals("local", pyenv.current().origin)
    end)
  end)

  describe("notifications", function()
    ---Configure once, then activate `times` times, so the "did anything change?"
    ---comparison actually has a previous value to compare against.
    local function capture(mode, cwd, times)
      configure({ notify = mode })
      local messages = {}
      for _ = 1, (times or 1) do
        pyenv.activate({
          cwd = cwd,
          notify = function(msg, level)
            table.insert(messages, { msg = msg, level = level })
          end,
        })
      end
      return messages
    end

    it("announces the first activation but stays quiet when nothing changed", function()
      local proj = fx.project({ [".python-version"] = "3.12.4\n" })
      assert.equals(1, #capture("changes", proj, 3))
    end)

    it("announces a genuine change", function()
      configure({ notify = "changes" })
      local messages = {}
      local function notify(msg, level)
        table.insert(messages, { msg = msg, level = level })
      end

      pyenv.activate({ cwd = fx.project({ [".python-version"] = "3.12.4\n" }), notify = notify })
      pyenv.activate({ cwd = fx.project({ [".python-version"] = "3.11.9\n" }), notify = notify })

      assert.equals(2, #messages)
      assert.is_truthy(messages[2].msg:match("3%.11%.9"))
    end)

    it("announces every activation when set to all", function()
      local proj = fx.project({ [".python-version"] = "3.12.4\n" })
      assert.equals(3, #capture("all", proj, 3))
    end)

    it("says nothing at all when disabled", function()
      assert.equals(0, #capture(false, fx.project({ [".python-version"] = "3.13.0\n" })))
    end)

    it("warns about a version that is not installed, even in errors mode", function()
      local messages = capture("errors", fx.project({ [".python-version"] = "3.13.0\n" }))
      assert.equals(1, #messages)
      assert.equals(vim.log.levels.WARN, messages[1].level)
      assert.is_truthy(messages[1].msg:match("3%.13%.0 is not installed"))
      assert.is_truthy(messages[1].msg:match("%.python%-version"))
    end)

    it("stays quiet about ordinary activations in errors mode", function()
      assert.equals(0, #capture("errors", fx.project({ [".python-version"] = "3.12.4\n" })))
    end)
  end)

  describe("status", function()
    it("is empty before anything is activated", function()
      state.set_current(nil)
      assert.equals("", pyenv.status())
    end)

    it("shows a plain version", function()
      pyenv.activate({ cwd = fx.project({ [".python-version"] = "3.12.4\n" }) })
      assert.equals("3.12.4", pyenv.status())
    end)

    it("shows a virtualenv with the version it was built from", function()
      pyenv.activate({ cwd = fx.project({ [".python-version"] = "proj-env\n" }) })
      assert.equals("proj-env (3.12.4)", pyenv.status())
    end)

    it("marks a version that is not installed", function()
      pyenv.activate({
        cwd = fx.project({ [".python-version"] = "3.13.0\n" }),
        notify = function() end,
      })
      assert.equals("3.13.0 (missing)", pyenv.status())
    end)
  end)

  describe("list", function()
    it("returns the installed environments", function()
      local names = vim.tbl_map(function(e)
        return e.name
      end, pyenv.list())
      assert.same({ "3.11.9", "3.12.4", "proj-env" }, names)
    end)
  end)
end)
