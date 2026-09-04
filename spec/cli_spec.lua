local cli = require("pyenv.cli")
local config = require("pyenv.config")
local fx = require("fixtures")

---A stand-in for vim.system that records the call and hands back the handlers.
local function fake_system(captured)
  return function(cmd, opts, on_exit)
    captured.cmd = cmd
    captured.opts = opts
    captured.on_exit = on_exit
    return {
      kill = function()
        captured.killed = true
      end,
    }
  end
end

describe("pyenv.cli", function()
  local saved_env

  before_each(function()
    saved_env = { HOME = vim.env.HOME, PYENV_ROOT = vim.env.PYENV_ROOT }
  end)

  after_each(function()
    config.reset()
    vim.env.HOME = saved_env.HOME
    vim.env.PYENV_ROOT = saved_env.PYENV_ROOT
    fx.cleanup()
  end)

  describe("run", function()
    it("invokes the pyenv binary with the given arguments", function()
      local captured = {}
      cli.run({ "install", "3.12.4" }, {}, {
        system = fake_system(captured),
        binary = "/opt/pyenv/bin/pyenv",
      })
      assert.same({ "/opt/pyenv/bin/pyenv", "install", "3.12.4" }, captured.cmd)
      assert.is_true(captured.opts.text)
    end)

    it("returns a handle that can cancel the process", function()
      local captured = {}
      local handle = cli.run({ "install", "3.12.4" }, {}, {
        system = fake_system(captured),
        binary = "/bin/pyenv",
      })
      handle:kill()
      assert.is_true(captured.killed)
    end)

    it("starts the child in its own process group", function()
      -- So that cancelling can signal the group. `pyenv install` is a bash
      -- script; a signal to it alone leaves python-build and make running.
      local captured = {}
      cli.run({ "install", "3.12.4" }, {}, {
        system = fake_system(captured),
        binary = "/bin/pyenv",
      })
      assert.is_true(captured.opts.detach)
    end)

    it("refuses to run without the pyenv binary", function()
      local notified
      local saved = vim.notify
      vim.notify = function(msg, level)
        notified = { msg = msg, level = level }
      end

      local handle = cli.run({ "rehash" }, {}, { binary = false })
      vim.notify = saved

      assert.is_nil(handle)
      assert.equals(vim.log.levels.ERROR, notified.level)
      assert.is_truthy(notified.msg:match("checkhealth pyenv"))
    end)

    it("reassembles whole lines from arbitrary stream chunks", function()
      -- vim.system delivers whatever the pipe gives it, which splits lines at
      -- unhelpful places; a naive handler would emit "tw" and "o" separately.
      local captured, lines = {}, {}
      cli.run({ "install", "--list" }, {
        on_output = function(line)
          lines[#lines + 1] = line
        end,
      }, { system = fake_system(captured), binary = "/bin/pyenv" })

      captured.opts.stdout(nil, "one\ntw")
      captured.opts.stdout(nil, "o\nthree\n")
      vim.wait(200, function()
        return #lines >= 3
      end)

      assert.same({ "one", "two", "three" }, lines)
    end)

    it("keeps stdout and stderr from corrupting each other's partial lines", function()
      -- The two pipes arrive independently and interleaved. A line buffer shared
      -- between them splices a whole stderr line into the middle of a half-read
      -- stdout one, which is exactly what `pyenv install` produces for minutes.
      local captured, lines = {}, {}
      cli.run({ "install", "3.12.4" }, {
        on_output = function(line)
          lines[#lines + 1] = line
        end,
      }, { system = fake_system(captured), binary = "/bin/pyenv" })

      captured.opts.stdout(nil, "Downloading Python-3.12.4") -- partial
      captured.opts.stderr(nil, "WARNING: build deps missing\n") -- complete
      captured.opts.stdout(nil, ".tar.xz...\n") -- the rest of the partial line
      vim.wait(200, function()
        return #lines >= 2
      end)

      assert.same({ "WARNING: build deps missing", "Downloading Python-3.12.4.tar.xz..." }, lines)
    end)

    it("flushes each stream's trailing line separately", function()
      local captured, lines = {}, {}
      cli.run({ "version-name" }, {
        on_output = function(line)
          lines[#lines + 1] = line
        end,
      }, { system = fake_system(captured), binary = "/bin/pyenv" })

      captured.opts.stdout(nil, "3.12.4")
      captured.opts.stderr(nil, "warning")
      captured.opts.stdout(nil, nil)
      captured.opts.stderr(nil, nil)
      vim.wait(200, function()
        return #lines >= 2
      end)

      table.sort(lines)
      assert.same({ "3.12.4", "warning" }, lines)
    end)

    it("flushes a trailing line that has no newline", function()
      local captured, lines = {}, {}
      cli.run({ "version-name" }, {
        on_output = function(line)
          lines[#lines + 1] = line
        end,
      }, { system = fake_system(captured), binary = "/bin/pyenv" })

      captured.opts.stdout(nil, "3.12.4")
      captured.opts.stdout(nil, nil) -- end of stream
      vim.wait(200, function()
        return #lines >= 1
      end)

      assert.same({ "3.12.4" }, lines)
    end)

    it("reports the exit code", function()
      local captured, code = {}, nil
      cli.run({ "install", "bogus" }, {
        on_exit = function(c)
          code = c
        end,
      }, { system = fake_system(captured), binary = "/bin/pyenv" })

      captured.on_exit({ code = 2 })
      vim.wait(200, function()
        return code ~= nil
      end)

      assert.equals(2, code)
    end)

    it("reports a killed command as failed, not as a silent success", function()
      -- A process that dies from a signal exits with code 0 and the signal
      -- reported separately, so a cancelled install would otherwise run the
      -- caller's success path: "installed 3.12.9" for a build that was killed
      -- half way through. 128 + signal is the shell's own convention.
      local captured, code = {}, nil
      cli.run({ "install", "3.12.4" }, {
        on_exit = function(c)
          code = c
        end,
      }, { system = fake_system(captured), binary = "/bin/pyenv" })

      captured.on_exit({ code = 0, signal = 15 })
      vim.wait(200, function()
        return code ~= nil
      end)

      assert.equals(143, code)
    end)
  end)

  describe("stop", function()
    ---@return table handle, table[] signals
    local function fake(pid)
      local signals = {}
      local handle = {
        pid = pid,
        kill = function(_, signal)
          signals[#signals + 1] = { target = "handle", signal = signal }
        end,
      }
      return handle, signals
    end

    it("signals the whole process group, not just the child", function()
      -- The child is a bash script; python-build, make and the compiler it
      -- spawns are the processes that actually need to stop.
      local handle = fake(4242)
      local killed
      assert.is_true(cli.stop(handle, {
        kill = function(pid, signal)
          killed = { pid = pid, signal = signal }
        end,
      }))
      assert.equals(-4242, killed.pid)
    end)

    it("refuses a pid that would signal Neovim's own process group", function()
      -- kill(-0) means "every process in the caller's group", which includes
      -- Neovim. Nothing is worth that.
      local killed = false
      local function kill()
        killed = true
      end

      for _, pid in ipairs({ 0, 1, -9 }) do
        local handle = fake(pid)
        assert.is_false(cli.stop(handle, { kill = kill }))
      end
      assert.is_false(cli.stop(nil, { kill = kill }))
      assert.is_false(cli.stop({}, { kill = kill }))
      assert.is_false(killed)
    end)

    it("falls back to the child alone when the group cannot be signalled", function()
      local handle, signals = fake(4242)
      assert.is_true(cli.stop(handle, {
        kill = function()
          error("no such process group")
        end,
      }))
      assert.equals("handle", signals[1].target)
    end)
  end)

  describe("parse_available", function()
    it("strips the header and the indentation", function()
      assert.same(
        { "3.11.9", "3.12.4", "pypy3.10-7.3.15" },
        cli.parse_available({
          "Available versions:",
          "  3.11.9",
          "  3.12.4",
          "",
          "  pypy3.10-7.3.15",
        })
      )
    end)

    it("copes with empty output", function()
      assert.same({}, cli.parse_available({}))
    end)
  end)
end)
