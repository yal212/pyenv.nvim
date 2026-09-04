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

describe("pyenv.integrations.lsp restart", function()
  ---A controllable stand-in for the Neovim LSP surface. `defer` queues
  ---callbacks instead of using real timers, so the test drives the clock.
  local function harness(opts)
    local h =
      { log = {}, started = {}, clients = opts.clients or {}, enabled = opts.enabled, queue = {} }

    h.deps = {
      get_clients = function()
        return h.clients
      end,
      is_enabled = function()
        return h.enabled
      end,
      enable = function(name, on)
        table.insert(h.log, ("enable %s %s"):format(name, tostring(on)))
      end,
      exec_autocmds = function(event, o)
        table.insert(h.log, ("%s buf=%d"):format(event, o.buffer))
      end,
      defer = function(fn)
        table.insert(h.queue, fn)
      end,
      start = function(config, o)
        table.insert(h.log, ("start buf=%d"):format(o.bufnr))
        table.insert(h.started, { root = config.root_dir, buf = o.bufnr })
      end,
      buf_is_valid = function()
        return true
      end,
    }

    ---Run every queued callback once.
    function h.tick()
      local due = h.queue
      h.queue = {}
      for _, fn in ipairs(due) do
        fn()
      end
    end

    return h
  end

  local function client(name, buf)
    return {
      name = name,
      config = { name = name },
      attached_buffers = { [buf] = true },
      stop = function(self)
        self.stopped = true
      end,
    }
  end

  ---A client with its own workspace root and its own set of attached buffers.
  local function client_at(name, root, buffers)
    local attached = {}
    for _, buf in ipairs(buffers) do
      attached[buf] = true
    end
    return {
      name = name,
      config = { name = name, root_dir = root },
      attached_buffers = attached,
      stop = function(self)
        self.stopped = true
      end,
    }
  end

  it("does not re-enable until the old client has actually exited", function()
    -- Disabling stops clients asynchronously. Re-enabling in the same tick
    -- races the shutdown and leaves the buffer with no server at all.
    local h = harness({ enabled = true, clients = { client("pyright", 7) } })
    lsp.restart("pyright", h.deps)
    assert.same({ "enable pyright false" }, h.log)

    h.tick() -- still running
    assert.same({ "enable pyright false" }, h.log)

    h.clients = {} -- the server has now exited
    h.tick()
    assert.same({ "enable pyright false", "enable pyright true", "FileType buf=7" }, h.log)
  end)

  it("re-fires FileType so an already-open buffer gets the server back", function()
    -- vim.lsp.enable() only auto-activates on *future* buffer events; without
    -- this nudge the buffer the user is looking at never re-attaches.
    local h = harness({ enabled = true, clients = { client("pyright", 3) } })
    lsp.restart("pyright", h.deps)
    h.clients = {}
    h.tick()

    assert.is_true(vim.tbl_contains(h.log, "FileType buf=3"))
  end)

  it("gives up waiting rather than hanging forever", function()
    local h = harness({ enabled = true, clients = { client("pyright", 1) } })
    lsp.restart("pyright", h.deps)

    for _ = 1, (lsp.STOP_TIMEOUT_MS / 100) + 2 do
      h.tick() -- the client never exits
    end

    assert.is_true(vim.tbl_contains(h.log, "enable pyright true"))
  end)

  it("stops and restarts per buffer when the config is not vim.lsp.enable-governed", function()
    local c = client("pyright", 9)
    local h = harness({ enabled = false, clients = { c } })
    lsp.restart("pyright", h.deps)

    assert.is_true(c.stopped)
    h.clients = {}
    h.tick()
    assert.same({ "start buf=9" }, h.log)
  end)

  it("restarts each client into its own buffers, not into every buffer", function()
    -- Two workspace roots open at once. Flattening every config and every buffer
    -- into two independent lists and starting the cross-product gives each
    -- buffer a duplicate server rooted at the wrong workspace.
    local h = harness({
      enabled = false,
      clients = {
        client_at("pyright", "/work/A", { 1, 2 }),
        client_at("pyright", "/work/B", { 7 }),
      },
    })
    lsp.restart("pyright", h.deps)
    h.clients = {}
    h.tick()

    -- attached_buffers is a set, so the order within one client is arbitrary.
    table.sort(h.started, function(a, b)
      return a.buf < b.buf
    end)
    assert.same({
      { root = "/work/A", buf = 1 },
      { root = "/work/A", buf = 2 },
      { root = "/work/B", buf = 7 },
    }, h.started)
  end)

  it("skips a client that has no config to start from", function()
    local h = harness({
      enabled = false,
      clients = {
        { name = "pyright", attached_buffers = { [5] = true }, stop = function() end },
        client_at("pyright", "/work/A", { 6 }),
      },
    })
    assert.has_no.errors(function()
      lsp.restart("pyright", h.deps)
      h.clients = {}
      h.tick()
    end)
    assert.same({ { root = "/work/A", buf = 6 } }, h.started)
  end)

  it("re-fires FileType once per buffer when two clients share one", function()
    local h = harness({
      enabled = true,
      clients = {
        client_at("pyright", "/work/A", { 4 }),
        client_at("pyright", "/work/B", { 4 }),
      },
    })
    lsp.restart("pyright", h.deps)
    h.clients = {}
    h.tick()

    local fired = 0
    for _, entry in ipairs(h.log) do
      if entry == "FileType buf=4" then
        fired = fired + 1
      end
    end
    assert.equals(1, fired)
  end)
end)
