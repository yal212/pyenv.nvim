local config = require("pyenv.config")

describe("pyenv.config", function()
  after_each(function()
    config.reset()
  end)

  it("exposes sane defaults before setup is ever called", function()
    local c = config.get()
    assert.is_true(c.auto_activate)
    assert.is_true(c.lsp.enabled)
    assert.same(config.defaults.resolution_order, c.resolution_order)
  end)

  it("deep-merges user options over defaults", function()
    config.setup({ lsp = { enabled = false } })
    local c = config.get()
    assert.is_false(c.lsp.enabled)
    -- untouched sibling keys survive the merge
    assert.same({ "pyright", "basedpyright", "pylsp" }, c.lsp.servers)
    assert.is_true(c.auto_activate)
  end)

  it("replaces list-like options wholesale rather than merging them", function()
    -- Deep-merging arrays would make it impossible to shorten a list.
    config.setup({ lsp = { servers = { "pyright" } } })
    assert.same({ "pyright" }, config.get().lsp.servers)
  end)

  it("does not mutate the defaults table", function()
    config.setup({ lsp = { servers = { "pyright" } } })
    config.reset()
    assert.same({ "pyright", "basedpyright", "pylsp" }, config.get().lsp.servers)
  end)

  it("rejects an unknown top-level option", function()
    assert.has_error(function()
      config.setup({ nonsense = true })
    end, "pyenv.nvim: unknown option 'nonsense'")
  end)

  it("rejects an unknown nested option", function()
    assert.has_error(function()
      config.setup({ lsp = { nonsense = true } })
    end, "pyenv.nvim: unknown option 'lsp.nonsense'")
  end)

  it("rejects an option of the wrong type", function()
    assert.has_error(function()
      config.setup({ auto_activate = "yes" })
    end, "pyenv.nvim: option 'auto_activate' expects boolean, got string")
  end)

  it("rejects an unknown resolution step", function()
    assert.has_error(function()
      config.setup({ resolution_order = { "local", "bogus" } })
    end, "pyenv.nvim: unknown resolution step 'bogus'")
  end)

  it("defaults to updating a running server in place", function()
    assert.equals("notify", config.get().lsp.strategy)
  end)

  it("accepts the restart strategy", function()
    config.setup({ lsp = { strategy = "restart" } })
    assert.equals("restart", config.get().lsp.strategy)
  end)

  it("rejects an unknown lsp strategy", function()
    -- Falling through to the default would leave a running server pointed at
    -- the old interpreter with nothing said about it.
    assert.has_error(function()
      config.setup({ lsp = { strategy = "reboot" } })
    end, "pyenv.nvim: unknown lsp strategy 'reboot'")
  end)

  it("accepts every notify level", function()
    for _, level in ipairs({ "all", "changes", "errors" }) do
      config.setup({ notify = level })
      assert.equals(level, config.get().notify)
    end
    config.setup({ notify = false })
    assert.is_false(config.get().notify)
  end)

  it("takes notify = true as a way of spelling all", function()
    -- false means off, so true meaning on is the only reading available. It is
    -- normalised here so nothing downstream has to know about the second
    -- spelling.
    config.setup({ notify = true })
    assert.equals("all", config.get().notify)
  end)

  it("rejects a misspelled notify level", function()
    assert.has_error(function()
      config.setup({ notify = "chages" })
    end, "pyenv.nvim: unknown notify level 'chages' (expected 'all', 'changes', 'errors' or false)")
  end)

  it('rejects the string "false", which used to mean the opposite', function()
    -- The nastiest of the typos this catches: a string passes the type check,
    -- matches none of announce()'s early returns, and so notifies on every
    -- single resolution -- exactly what asking for "false" meant to prevent.
    assert.has_error(function()
      config.setup({ notify = "false" })
    end, "pyenv.nvim: unknown notify level 'false' (expected 'all', 'changes', 'errors' or false)")
  end)

  it("allows nil for options that default to nil", function()
    assert.has_no.errors(function()
      config.setup({ root = "/opt/pyenv" })
    end)
    assert.equals("/opt/pyenv", config.get().root)
  end)

  it("accepts being called with no arguments", function()
    assert.has_no.errors(function()
      config.setup()
    end)
  end)
end)
