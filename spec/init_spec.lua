local fx = require("fixtures")
local config = require("pyenv.config")
local pyenv = require("pyenv")
local session = require("pyenv.session")
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
    -- The environment snapshot is taken once per process and survives a reload,
    -- so drop the previous case's before setup() takes this one's.
    session.forget()

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

    it("does not let a later setup() re-snapshot the plugin's own exports", function()
      -- setup() may be called again at runtime -- from a keymap, or by a plugin
      -- manager reloading the spec. If it re-took the snapshot then, it would
      -- read back the PYENV_VERSION the first activation exported and every
      -- directory from that point on would keep the first project's version.
      local a = fx.project({ [".python-version"] = "3.12.4\n" })
      local b = fx.project({ [".python-version"] = "3.11.9\n" })

      assert.equals("3.12.4", pyenv.activate({ cwd = a }).version)
      configure()

      assert.equals("3.11.9", pyenv.activate({ cwd = b }).version)
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

  describe("python3_host_prog", function()
    local saved_host_prog

    before_each(function()
      saved_host_prog = vim.g.python3_host_prog
    end)

    after_each(function()
      vim.g.python3_host_prog = saved_host_prog
    end)

    it("points the Python host at the active interpreter", function()
      configure({ python3_host_prog = true })
      pyenv.activate({ cwd = fx.project({ [".python-version"] = "3.12.4\n" }) })

      assert.equals(root .. "/versions/3.12.4/bin/python", vim.g.python3_host_prog)
    end)

    it("clears it when the environment is no longer usable", function()
      -- Regression guard for #22. Every other exported value is reverted when
      -- the resolution turns out to be unusable; declining to *set* this one
      -- left it pointing at the previous project's interpreter, so remote
      -- plugins kept running against an environment PATH, PYENV_VERSION and
      -- VIRTUAL_ENV had all already let go of.
      -- Nothing of the user's to put back, so "revert" means clear. Set before
      -- the snapshot is taken, so the case does not depend on what an earlier
      -- test happened to leave behind.
      vim.g.python3_host_prog = nil
      session.forget()
      configure({ python3_host_prog = true })

      pyenv.activate({ cwd = fx.project({ [".python-version"] = "3.12.4\n" }) })
      assert.is_truthy(vim.g.python3_host_prog)

      pyenv.activate({ cwd = fx.project({ [".python-version"] = "3.13.0\n" }) })

      assert.is_nil(vim.g.python3_host_prog)
    end)

    it("restores the value the user set, rather than flattening it", function()
      -- The snapshot is taken before the plugin has exported anything, so what
      -- goes back is the user's own host, not nil. This mirrors PATH, which
      -- subtracts only the entry the plugin added.
      vim.g.python3_host_prog = "/usr/bin/python3"
      session.forget()
      configure({ python3_host_prog = true })

      pyenv.activate({ cwd = fx.project({ [".python-version"] = "3.12.4\n" }) })
      assert.equals(root .. "/versions/3.12.4/bin/python", vim.g.python3_host_prog)

      pyenv.activate({ cwd = fx.project({ [".python-version"] = "3.13.0\n" }) })
      assert.equals("/usr/bin/python3", vim.g.python3_host_prog)
    end)

    it("leaves the variable alone when the option is off", function()
      vim.g.python3_host_prog = "/usr/bin/python3"
      configure() -- python3_host_prog defaults to false
      pyenv.activate({ cwd = fx.project({ [".python-version"] = "3.12.4\n" }) })

      assert.equals("/usr/bin/python3", vim.g.python3_host_prog)
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
