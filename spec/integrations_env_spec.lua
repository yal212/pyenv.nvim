local fx = require("fixtures")
local env = require("pyenv.integrations.env")

---Count exact-match entries in PATH.
local function path_entries(dir)
  local n = 0
  for entry in vim.gsplit(vim.env.PATH or "", ":", { plain = true }) do
    if entry == dir then
      n = n + 1
    end
  end
  return n
end

local function first_path_entry()
  return vim.split(vim.env.PATH or "", ":", { plain = true })[1]
end

describe("pyenv.integrations.env", function()
  local saved
  local all = { set_path = true, set_virtual_env = true }

  before_each(function()
    saved = {
      PATH = vim.env.PATH,
      PYENV_VERSION = vim.env.PYENV_VERSION,
      VIRTUAL_ENV = vim.env.VIRTUAL_ENV,
    }
    vim.env.PATH = "/usr/bin:/bin"
    vim.env.PYENV_VERSION = nil
    vim.env.VIRTUAL_ENV = nil
    env.reset()
  end)

  after_each(function()
    env.reset()
    vim.env.PATH = saved.PATH
    vim.env.PYENV_VERSION = saved.PYENV_VERSION
    vim.env.VIRTUAL_ENV = saved.VIRTUAL_ENV
    fx.cleanup()
  end)

  local function version(prefix, name)
    return { version = name, kind = "version", prefix = prefix, python = prefix .. "/bin/python" }
  end

  describe("PATH", function()
    it("prepends the environment's bin directory", function()
      env.apply(version("/pyenv/versions/3.12.4", "3.12.4"), all)
      assert.equals("/pyenv/versions/3.12.4/bin", first_path_entry())
      assert.equals("/usr/bin:/bin", vim.env.PATH:sub(-#"/usr/bin:/bin"))
    end)

    it("does not accumulate entries across repeated switches", function()
      -- The classic bug in this plugin category: every switch leaks another
      -- stale bin directory onto PATH until it is unusable.
      env.apply(version("/pyenv/versions/3.11.9", "3.11.9"), all)
      env.apply(version("/pyenv/versions/3.12.4", "3.12.4"), all)
      env.apply(version("/pyenv/versions/3.13.0", "3.13.0"), all)

      assert.equals(0, path_entries("/pyenv/versions/3.11.9/bin"))
      assert.equals(0, path_entries("/pyenv/versions/3.12.4/bin"))
      assert.equals(1, path_entries("/pyenv/versions/3.13.0/bin"))
      assert.equals("/usr/bin:/bin", vim.env.PATH:sub(-#"/usr/bin:/bin"))
    end)

    it("is idempotent when the same environment is applied twice", function()
      env.apply(version("/pyenv/versions/3.12.4", "3.12.4"), all)
      env.apply(version("/pyenv/versions/3.12.4", "3.12.4"), all)
      assert.equals(1, path_entries("/pyenv/versions/3.12.4/bin"))
    end)

    it("leaves one entry when switching back to a previous environment", function()
      env.apply(version("/pyenv/versions/3.11.9", "3.11.9"), all)
      env.apply(version("/pyenv/versions/3.12.4", "3.12.4"), all)
      env.apply(version("/pyenv/versions/3.11.9", "3.11.9"), all)

      assert.equals(1, path_entries("/pyenv/versions/3.11.9/bin"))
      assert.equals(0, path_entries("/pyenv/versions/3.12.4/bin"))
    end)

    it("does not duplicate a bin directory the user already had on PATH", function()
      vim.env.PATH = "/pyenv/versions/3.12.4/bin:/usr/bin:/bin"
      env.apply(version("/pyenv/versions/3.12.4", "3.12.4"), all)
      assert.equals(1, path_entries("/pyenv/versions/3.12.4/bin"))
    end)

    it("restores PATH on reset", function()
      env.apply(version("/pyenv/versions/3.12.4", "3.12.4"), all)
      env.reset()
      assert.equals("/usr/bin:/bin", vim.env.PATH)
    end)

    it("leaves PATH alone when set_path is false", function()
      env.apply(version("/pyenv/versions/3.12.4", "3.12.4"), { set_path = false })
      assert.equals("/usr/bin:/bin", vim.env.PATH)
    end)

    it("does not point PATH at an environment that is not installed", function()
      -- A .python-version naming an uninstalled version resolves to a
      -- synthesised prefix that does not exist. lsp, dap and python3_host_prog
      -- all decline to wire that up; PATH must not be the odd one out.
      env.apply({
        version = "3.11.9",
        kind = "version",
        prefix = "/pyenv/versions/3.11.9",
        python = "/pyenv/versions/3.11.9/bin/python",
        missing = true,
      }, all)

      assert.equals(0, path_entries("/pyenv/versions/3.11.9/bin"))
      assert.equals("/usr/bin:/bin", vim.env.PATH)
    end)

    it("removes the previous environment when the next one is missing", function()
      env.apply(version("/pyenv/versions/3.12.4", "3.12.4"), all)
      env.apply({
        version = "3.11.9",
        kind = "version",
        prefix = "/pyenv/versions/3.11.9",
        python = "/pyenv/versions/3.11.9/bin/python",
        missing = true,
      }, all)

      assert.equals(0, path_entries("/pyenv/versions/3.12.4/bin"))
      assert.equals("/usr/bin:/bin", vim.env.PATH)
    end)

    it("tolerates a resolution with no prefix", function()
      assert.has_no.errors(function()
        env.apply({ version = "system", kind = "system", python = "/usr/bin/python3" }, all)
      end)
      assert.equals("/usr/bin:/bin", vim.env.PATH)
    end)
  end)

  describe("PYENV_VERSION", function()
    it("is set for an installed version", function()
      env.apply(version("/pyenv/versions/3.12.4", "3.12.4"), all)
      assert.equals("3.12.4", vim.env.PYENV_VERSION)
    end)

    it("is set for a pyenv virtualenv", function()
      env.apply({
        version = "proj-env",
        kind = "virtualenv",
        prefix = "/pyenv/versions/3.12.4/envs/proj-env",
        parent = "3.12.4",
      }, all)
      assert.equals("proj-env", vim.env.PYENV_VERSION)
    end)

    it("is unset for a non-pyenv project venv", function()
      -- Exporting PYENV_VERSION=".venv" would make every pyenv subprocess fail.
      vim.env.PYENV_VERSION = "3.12.4"
      env.apply({ version = ".venv", kind = "venv", prefix = "/proj/.venv" }, all)
      assert.is_nil(vim.env.PYENV_VERSION)
    end)

    it("is unset for system python", function()
      vim.env.PYENV_VERSION = "3.12.4"
      env.apply({ version = "system", kind = "system" }, all)
      assert.is_nil(vim.env.PYENV_VERSION)
    end)
  end)

  describe("VIRTUAL_ENV", function()
    it("is set for a pyenv virtualenv", function()
      env.apply({
        version = "proj-env",
        kind = "virtualenv",
        prefix = "/pyenv/versions/3.12.4/envs/proj-env",
      }, all)
      assert.equals("/pyenv/versions/3.12.4/envs/proj-env", vim.env.VIRTUAL_ENV)
    end)

    it("is set for a project venv", function()
      env.apply({ version = ".venv", kind = "venv", prefix = "/proj/.venv" }, all)
      assert.equals("/proj/.venv", vim.env.VIRTUAL_ENV)
    end)

    it("is unset when switching to a plain version", function()
      env.apply({ version = "proj-env", kind = "virtualenv", prefix = "/p/envs/proj-env" }, all)
      env.apply(version("/pyenv/versions/3.12.4", "3.12.4"), all)
      assert.is_nil(vim.env.VIRTUAL_ENV)
    end)

    it("leaves VIRTUAL_ENV alone when set_virtual_env is false", function()
      vim.env.VIRTUAL_ENV = "/somewhere/else"
      env.apply({ version = "proj-env", kind = "virtualenv", prefix = "/p" }, { set_path = true })
      assert.equals("/somewhere/else", vim.env.VIRTUAL_ENV)
    end)
  end)
end)
