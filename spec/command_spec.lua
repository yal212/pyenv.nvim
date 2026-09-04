local cli = require("pyenv.cli")
local command = require("pyenv.command")
local config = require("pyenv.config")
local fx = require("fixtures")
local pyenv = require("pyenv")
local state = require("pyenv.state")

describe("pyenv.command", function()
  local root, saved_env, saved_notify, saved_run, notifications

  before_each(function()
    -- command.lua holds a reference to this very table, so replacing the field
    -- swaps the implementation out from under it without touching the module.
    saved_run = cli.run

    saved_env = { PATH = vim.env.PATH, PYENV_VERSION = vim.env.PYENV_VERSION }
    vim.env.PATH = "/usr/bin:/bin"
    vim.env.PYENV_VERSION = nil

    root = fx.pyenv_root({
      versions = { "3.11.9", "3.12.4" },
      virtualenvs = { ["3.12.4"] = { "proj-env" } },
      global = "3.11.9",
    })
    pyenv.setup({
      root = root,
      lsp = { enabled = false },
      dap = { enabled = false },
      cache = { enabled = false },
      notify = false,
    })

    notifications = {}
    saved_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end
  end)

  after_each(function()
    cli.run = saved_run
    vim.notify = saved_notify
    require("pyenv.integrations.env").reset()
    config.reset()
    state.reset()
    for k, v in pairs(saved_env) do
      vim.env[k] = v
    end
    fx.cleanup()
  end)

  describe("completion", function()
    it("offers subcommands when none has been typed", function()
      local got = command.complete("", "Pyenv ")
      assert.is_true(vim.tbl_contains(got, "select"))
      assert.is_true(vim.tbl_contains(got, "activate"))
      assert.is_true(vim.tbl_contains(got, "status"))
    end)

    it("filters subcommands by prefix", function()
      assert.same({ "select" }, command.complete("se", "Pyenv se"))
    end)

    it("offers environment names as the argument to activate", function()
      local got = command.complete("", "Pyenv activate ")
      assert.is_true(vim.tbl_contains(got, "3.12.4"))
      assert.is_true(vim.tbl_contains(got, "proj-env"))
      assert.is_true(vim.tbl_contains(got, "system"))
    end)

    it("filters environment names by prefix", function()
      assert.same({ "3.12.4" }, command.complete("3.12", "Pyenv activate 3.12"))
    end)

    it("offers nothing for a subcommand that takes no arguments", function()
      assert.same({}, command.complete("", "Pyenv reset "))
    end)

    it("offers nothing once the argument is already given", function()
      assert.same({}, command.complete("", "Pyenv activate 3.12.4 "))
    end)

    it("offers nothing for an unknown subcommand", function()
      assert.same({}, command.complete("", "Pyenv bogus "))
    end)
  end)

  describe("dispatch", function()
    it("reports an unknown subcommand and lists the valid ones", function()
      command.run({ fargs = { "bogus" } })

      assert.equals(1, #notifications)
      assert.equals(vim.log.levels.ERROR, notifications[1].level)
      assert.is_truthy(notifications[1].msg:match("unknown subcommand 'bogus'"))
      assert.is_truthy(notifications[1].msg:match("activate"))
    end)

    it("defaults to status when given no subcommand", function()
      command.run({ fargs = {} })
      assert.is_truthy(notifications[1].msg:match("environment"))
    end)

    it("explains where the active version came from", function()
      local proj = fx.project({ [".python-version"] = "3.12.4\n" })
      pyenv.activate({ cwd = proj })

      command.run({ fargs = { "status" } })
      local msg = notifications[#notifications].msg
      assert.is_truthy(msg:match("3%.12%.4"))
      assert.is_truthy(msg:match("%.python%-version at " .. vim.pesc(proj)))
    end)

    it("requires a name for activate", function()
      command.run({ fargs = { "activate" } })
      assert.equals(vim.log.levels.ERROR, notifications[1].level)
      assert.is_truthy(notifications[1].msg:match("usage"))
    end)

    it("writes .python-version for the local subcommand", function()
      local proj = fx.project({})
      local cwd = vim.fn.getcwd()
      vim.cmd.cd(proj)

      command.run({ fargs = { "local", "3.12.4" } })
      assert.same({ "3.12.4" }, vim.fn.readfile(proj .. "/.python-version"))

      vim.cmd.cd(cwd)
    end)

    it("sets the global version file", function()
      command.run({ fargs = { "global", "3.12.4" } })
      assert.same({ "3.12.4" }, vim.fn.readfile(root .. "/version"))
    end)

    it("reports the current global version when given no argument", function()
      command.run({ fargs = { "global" } })
      assert.is_truthy(notifications[#notifications].msg:match("3%.11%.9"))
    end)
  end)

  describe("install", function()
    it("says nothing about fetching when nothing was spawned", function()
      -- cli.run reports the missing binary and returns nil without spawning, so
      -- neither of its callbacks will ever fire. A "fetching..." message
      -- announced anyway would stand there with nothing able to resolve it.
      cli.run = function()
        return nil
      end

      command.run({ fargs = { "install" } })

      assert.equals(0, #notifications)
    end)

    it("announces the fetch once the process is running, and reports failure", function()
      local exit
      cli.run = function(_, opts)
        exit = opts.on_exit
        return { pid = 1 }
      end

      command.run({ fargs = { "install" } })
      assert.is_truthy(notifications[#notifications].msg:match("fetching"))

      exit(1)
      assert.equals(vim.log.levels.ERROR, notifications[#notifications].level)
      assert.is_truthy(notifications[#notifications].msg:match("could not list"))
    end)
  end)
end)
