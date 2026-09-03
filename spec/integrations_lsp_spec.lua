local lsp = require("pyenv.integrations.lsp")

local function resolution(python, extra)
  return vim.tbl_extend("force", {
    version = "3.12.4",
    kind = "version",
    python = python,
    prefix = "/pyenv/versions/3.12.4",
  }, extra or {})
end

--- A stand-in for a running LSP client, recording what was sent to it.
local function fake_client(name)
  return {
    name = name,
    settings = {},
    notified = {},
    notify = function(self, method, params)
      table.insert(self.notified, { method = method, params = params })
      return true
    end,
  }
end

describe("pyenv.integrations.lsp", function()
  local restarted, clients

  local function deps()
    return {
      get_clients = function(filter)
        return vim.tbl_filter(function(c)
          return c.name == filter.name
        end, clients)
      end,
      restart = function(name)
        restarted[name] = (restarted[name] or 0) + 1
      end,
    }
  end

  before_each(function()
    restarted, clients = {}, {}
    lsp.reset()
  end)

  after_each(function()
    lsp.reset()
  end)

  describe("static configuration", function()
    it("writes pythonPath for pyright so future clients start correctly", function()
      lsp.apply(
        resolution("/pyenv/versions/3.12.4/bin/python"),
        { servers = { "pyright" } },
        deps()
      )

      local cfg = vim.lsp.config.pyright
      assert.equals("/pyenv/versions/3.12.4/bin/python", cfg.settings.python.pythonPath)
    end)

    it("writes jedi.environment for pylsp", function()
      lsp.apply(resolution("/pyenv/versions/3.12.4/bin/python"), { servers = { "pylsp" } }, deps())

      local cfg = vim.lsp.config.pylsp
      assert.equals(
        "/pyenv/versions/3.12.4/bin/python",
        cfg.settings.pylsp.plugins.jedi.environment
      )
    end)

    it("exports VIRTUAL_ENV to the server process for a virtualenv", function()
      lsp.apply(
        resolution(
          "/p/envs/proj-env/bin/python",
          { kind = "virtualenv", prefix = "/p/envs/proj-env" }
        ),
        { servers = { "pyright" } },
        deps()
      )
      assert.equals("/p/envs/proj-env", vim.lsp.config.pyright.cmd_env.VIRTUAL_ENV)
    end)

    it("only touches the servers it was asked about", function()
      lsp.apply(resolution("/a/bin/python"), { servers = { "pyright" } }, deps())
      lsp.apply(resolution("/b/bin/python"), { servers = { "pylsp" } }, deps())

      assert.equals("/a/bin/python", vim.lsp.config.pyright.settings.python.pythonPath)
      assert.equals("/b/bin/python", vim.lsp.config.pylsp.settings.pylsp.plugins.jedi.environment)
    end)

    it("ignores server names it has no adapter for", function()
      assert.has_no.errors(function()
        lsp.apply(resolution("/a/bin/python"), { servers = { "not_a_server" } }, deps())
      end)
    end)
  end)

  describe("refusing to wire a broken environment", function()
    it("does nothing when the version is not installed", function()
      local before = vim.deepcopy(vim.lsp.config.pyright or {})
      lsp.apply(
        resolution("/pyenv/versions/3.13.0/bin/python", { missing = true }),
        { servers = { "pyright" } },
        deps()
      )
      assert.same(before.settings, (vim.lsp.config.pyright or {}).settings)
      assert.same({}, restarted)
    end)

    it("does nothing when there is no interpreter at all", function()
      clients = { fake_client("pyright") }
      lsp.apply(resolution(nil, { kind = "system" }), { servers = { "pyright" } }, deps())
      assert.same({}, restarted)
    end)
  end)

  describe("running clients", function()
    it("notifies pylsp rather than restarting it", function()
      local client = fake_client("pylsp")
      clients = { client }

      lsp.apply(resolution("/x/bin/python"), { servers = { "pylsp" } }, deps())
      vim.wait(200, function()
        return #client.notified > 0
      end)

      assert.equals(1, #client.notified)
      assert.equals("workspace/didChangeConfiguration", client.notified[1].method)
      assert.equals(
        "/x/bin/python",
        client.notified[1].params.settings.pylsp.plugins.jedi.environment
      )
      assert.is_nil(restarted.pylsp)
    end)

    it("restarts pyright, which does not reliably reload pythonPath", function()
      clients = { fake_client("pyright") }

      lsp.apply(resolution("/x/bin/python"), { servers = { "pyright" } }, deps())
      vim.wait(300, function()
        return restarted.pyright ~= nil
      end)

      assert.equals(1, restarted.pyright)
    end)

    it("coalesces a burst of switches into a single restart", function()
      -- A DirChanged burst must not thrash the language server.
      clients = { fake_client("pyright") }

      for _, p in ipairs({ "/a/bin/python", "/b/bin/python", "/c/bin/python" }) do
        lsp.apply(resolution(p), { servers = { "pyright" } }, deps())
      end
      vim.wait(300, function()
        return restarted.pyright ~= nil
      end)
      vim.wait(150) -- give any further restarts a chance to land

      assert.equals(1, restarted.pyright)
      -- the last value applied is the one that sticks
      assert.equals("/c/bin/python", vim.lsp.config.pyright.settings.python.pythonPath)
    end)

    it("does not restart a server that has no running client", function()
      clients = {}
      lsp.apply(resolution("/x/bin/python"), { servers = { "pyright" } }, deps())
      vim.wait(200)
      assert.is_nil(restarted.pyright)
    end)
  end)
end)
