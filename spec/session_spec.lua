local session = require("pyenv.session")

---Reload just this module, the way a plugin manager reloads the whole plugin.
---@return table the fresh module instance
local function reloaded()
  package.loaded["pyenv.session"] = nil
  local fresh = require("pyenv.session")
  -- Put the original table back so the rest of the suite keeps the instance it
  -- required at load time.
  package.loaded["pyenv.session"] = session
  return fresh
end

describe("pyenv.session", function()
  local saved

  before_each(function()
    saved = {
      PATH = vim.env.PATH,
      PYENV_VERSION = vim.env.PYENV_VERSION,
      VIRTUAL_ENV = vim.env.VIRTUAL_ENV,
      host_prog = vim.g.python3_host_prog,
    }
    vim.env.PATH = "/usr/bin:/bin"
    vim.env.PYENV_VERSION = nil
    vim.env.VIRTUAL_ENV = nil
    vim.g.python3_host_prog = nil
    session.forget()
  end)

  after_each(function()
    session.forget()
    vim.env.PATH = saved.PATH
    vim.env.PYENV_VERSION = saved.PYENV_VERSION
    vim.env.VIRTUAL_ENV = saved.VIRTUAL_ENV
    vim.g.python3_host_prog = saved.host_prog
  end)

  describe("original", function()
    it("captures the environment as it stands on the first call", function()
      vim.env.PYENV_VERSION = "3.12.4"
      vim.env.VIRTUAL_ENV = "/proj/.venv"

      local original = session.original()
      assert.equals("3.12.4", original.version)
      assert.equals("/proj/.venv", original.virtual_env)
      assert.equals("/usr/bin:/bin", original.path)
    end)

    it("records values that were unset as unset", function()
      local original = session.original()
      assert.is_nil(original.version)
      assert.is_nil(original.virtual_env)
      assert.is_nil(original.host_prog)
    end)

    it("captures g:python3_host_prog, which the plugin overwrites", function()
      -- Nothing resolves from the Python host; it is snapshotted so that an
      -- environment going away puts the user's own value back rather than
      -- clearing the variable outright (#22). Same rules as the rest of the
      -- snapshot: taken once, and inherited by a reloaded instance.
      vim.g.python3_host_prog = "/usr/bin/python3"
      session.forget()
      assert.equals("/usr/bin/python3", session.original().host_prog)

      vim.g.python3_host_prog = "/pyenv/versions/3.12.4/bin/python"
      assert.equals("/usr/bin/python3", session.original().host_prog)
      assert.equals("/usr/bin/python3", reloaded().original().host_prog)
    end)

    it("is not re-taken once the plugin has exported its own values", function()
      -- The whole point of the snapshot: reading it back after an activation
      -- would let an exported PYENV_VERSION win as a "shell" match forever.
      assert.is_nil(session.original().version)

      vim.env.PYENV_VERSION = "3.12.4"
      vim.env.PATH = "/pyenv/versions/3.12.4/bin:/usr/bin:/bin"

      assert.is_nil(session.original().version)
      assert.equals("/usr/bin:/bin", session.original().path)
    end)

    it("survives a reload of the module", function()
      -- Regression guard for #12. The snapshot describes the process, so a fresh
      -- module instance must inherit it rather than re-read what its predecessor
      -- exported.
      assert.is_nil(session.original().version)
      vim.env.PYENV_VERSION = "3.12.4"

      assert.is_nil(reloaded().original().version)
    end)

    it("is taken afresh after forget", function()
      assert.is_nil(session.original().version)

      vim.env.PYENV_VERSION = "3.11.9"
      session.forget()

      assert.equals("3.11.9", session.original().version)
    end)
  end)

  describe("path_entry", function()
    it("is unset until something is applied", function()
      assert.is_nil(session.path_entry())
    end)

    it("round-trips the bin directory", function()
      session.set_path_entry("/pyenv/versions/3.12.4/bin")
      assert.equals("/pyenv/versions/3.12.4/bin", session.path_entry())
    end)

    it("survives a reload of the module", function()
      -- Regression guard for #12. Without this a reloaded instance cannot remove
      -- its predecessor's entry, and every switch leaks another stale directory.
      session.set_path_entry("/pyenv/versions/3.12.4/bin")
      assert.equals("/pyenv/versions/3.12.4/bin", reloaded().path_entry())
    end)

    it("clears", function()
      session.set_path_entry("/pyenv/versions/3.12.4/bin")
      session.set_path_entry(nil)
      assert.is_nil(session.path_entry())
    end)
  end)

  describe("forget", function()
    it("drops both the snapshot and the path entry", function()
      session.original()
      session.set_path_entry("/pyenv/versions/3.12.4/bin")

      session.forget()

      assert.is_nil(session.path_entry())
      assert.is_nil(vim.g.pyenv_env_snapshot)
    end)
  end)
end)
