local cli = require("pyenv.cli")
local command = require("pyenv.command")
local config = require("pyenv.config")
local fx = require("fixtures")
local pyenv = require("pyenv")
local session = require("pyenv.session")
local state = require("pyenv.state")

describe("pyenv.command", function()
  local root, saved_env, saved_notify, saved_run, saved_stop, notifications

  before_each(function()
    -- command.lua holds a reference to this very table, so replacing the field
    -- swaps the implementation out from under it without touching the module.
    saved_run = cli.run
    saved_stop = cli.stop

    saved_env = { PATH = vim.env.PATH, PYENV_VERSION = vim.env.PYENV_VERSION }
    vim.env.PATH = "/usr/bin:/bin"
    vim.env.PYENV_VERSION = nil
    -- The environment snapshot is taken once per process and survives a reload,
    -- so drop the previous case's before setup() takes this one's.
    session.forget()

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
    cli.stop = saved_stop
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
    local saved_select, offered

    before_each(function()
      saved_select = vim.ui.select
      offered = nil
      vim.ui.select = function(items)
        offered = items
      end

      -- The version list is module state that outlives an example, and a warm
      -- cache would send the next test straight to the picker. --refresh clears
      -- it through the public surface; the stub means nothing is spawned to do
      -- so, and nothing is left in flight afterwards.
      cli.run = function()
        return nil
      end
      command.run({ fargs = { "install", "--refresh" } })
      notifications = {}
    end)

    after_each(function()
      vim.ui.select = saved_select
    end)

    it("stops the whole command when the progress window is cancelled", function()
      -- The floating window binds q to this. Nothing else takes a running
      -- install back down, so a handle that is not passed on is a build that
      -- keeps compiling with its window gone.
      local handle = { pid = 4242 }
      local stopped
      cli.run = function()
        return handle
      end
      cli.stop = function(given)
        stopped = given
      end

      command.run({ fargs = { "install", "3.12.4" } })

      local buf
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(b) and vim.bo[b].filetype == "pyenv-progress" then
          buf = b
        end
      end
      assert.is_truthy(buf)

      local cancel
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
        if map.lhs == "q" then
          cancel = map.callback
        end
      end
      assert.is_truthy(cancel)
      cancel()

      assert.equals(handle, stopped)
    end)

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

    it("primes the version list in the background on first completion", function()
      local spawned, exit = {}, nil
      cli.run = function(args, opts)
        spawned[#spawned + 1] = table.concat(args, " ")
        exit = function()
          opts.on_output("Available versions:")
          opts.on_output("  3.13.2")
          opts.on_output("  3.12.4")
          opts.on_exit(0)
        end
        return { pid = 1 }
      end

      -- Fetching inline would stall the keystroke for about a second, so the
      -- first <Tab> comes back empty and starts the fetch instead. Before this,
      -- nothing primed the cache and completion stayed empty all session.
      assert.same({}, command.complete("", "Pyenv install "))
      assert.same({ "install --list" }, spawned)

      exit()
      assert.same({ "--refresh", "3.13.2", "3.12.4" }, command.complete("", "Pyenv install "))
      assert.same({ "3.13.2" }, command.complete("3.13", "Pyenv install 3.13"))
    end)

    it("joins the fetch in flight rather than starting another", function()
      local spawned, last = 0, nil
      cli.run = function(_, opts)
        spawned = spawned + 1
        last = opts
        return { pid = 1 }
      end

      command.complete("", "Pyenv install ")
      command.complete("", "Pyenv install ")
      command.complete("3.1", "Pyenv install 3.1")

      assert.equals(1, spawned)

      last.on_exit(0)
      assert.equals(1, spawned)
    end)

    it("re-fetches the version list on --refresh", function()
      local spawned, exit = 0, nil
      cli.run = function(_, opts)
        spawned = spawned + 1
        exit = function(versions)
          for _, version in ipairs(versions) do
            opts.on_output(version)
          end
          opts.on_exit(0)
        end
        return { pid = 1 }
      end

      command.complete("", "Pyenv install ")
      exit({ "3.12.4" })
      assert.same({ "--refresh", "3.12.4" }, command.complete("", "Pyenv install "))

      command.run({ fargs = { "install", "--refresh" } })
      assert.equals(2, spawned)
      exit({ "3.12.4", "3.13.2" })

      assert.same({ "3.12.4", "3.13.2" }, offered)
      assert.same({ "--refresh", "3.12.4", "3.13.2" }, command.complete("", "Pyenv install "))
    end)
  end)
end)
