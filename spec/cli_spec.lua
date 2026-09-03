local cli = require("pyenv.cli")

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
