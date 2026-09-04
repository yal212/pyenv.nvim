local fx = require("fixtures")
local resolve = require("pyenv.resolve")

--- A PATH with no pyenv shims on it, so "system" resolution is deterministic.
local function bare_path()
  return "/usr/bin:/bin"
end

describe("pyenv.resolve", function()
  local root

  before_each(function()
    root = fx.pyenv_root({
      versions = { "3.11.9", "3.12.4" },
      virtualenvs = { ["3.12.4"] = { "proj-env" } },
      global = "3.11.9",
    })
  end)

  after_each(function()
    fx.cleanup()
  end)

  describe("chain order", function()
    it("prefers an explicit override above everything else", function()
      local r = resolve.resolve({
        root = root,
        cwd = fx.project({ [".python-version"] = "3.12.4\n" }),
        override = "proj-env",
        shell = "3.12.4",
        path = bare_path(),
      })
      assert.equals("proj-env", r.version)
      assert.equals("override", r.origin)
      assert.equals("virtualenv", r.kind)
    end)

    it("prefers PYENV_VERSION over .python-version", function()
      local r = resolve.resolve({
        root = root,
        cwd = fx.project({ [".python-version"] = "3.11.9\n" }),
        shell = "3.12.4",
        path = bare_path(),
      })
      assert.equals("3.12.4", r.version)
      assert.equals("shell", r.origin)
    end)

    it("prefers .python-version over the global version", function()
      local r = resolve.resolve({
        root = root,
        cwd = fx.project({ [".python-version"] = "3.12.4\n" }),
        path = bare_path(),
      })
      assert.equals("3.12.4", r.version)
      assert.equals("local", r.origin)
    end)

    it("prefers a project .venv over the global version", function()
      -- Deliberate divergence from pyenv: a global version is a machine-wide
      -- default, while a .venv is project-scoped and nearly always intended.
      local r = resolve.resolve({
        root = root,
        cwd = fx.project({ [".venv"] = true }),
        path = bare_path(),
      })
      assert.equals("project_venv", r.origin)
      assert.equals("venv", r.kind)
    end)

    it("prefers the nearest venv, not the nearest .venv", function()
      -- Searching all the way up for .venv before venv is tried at all lets a
      -- stray .venv in $HOME or at a monorepo root capture every venv-using
      -- project beneath it.
      local dir = fx.project({ [".venv"] = true, ["sub/venv"] = true })
      local r = resolve.resolve({ root = root, cwd = dir .. "/sub", path = bare_path() })

      assert.equals("project_venv", r.origin)
      assert.equals(dir .. "/sub/venv", r.prefix)
    end)

    it("prefers .venv over venv when both sit in the same directory", function()
      local dir = fx.project({ [".venv"] = true, ["venv"] = true })
      local r = resolve.resolve({ root = root, cwd = dir, path = bare_path() })

      assert.equals(dir .. "/.venv", r.prefix)
    end)

    it("skips a venv-shaped directory with no usable interpreter", function()
      local dir = fx.project({ ["sub/.venv/lib"] = "", ["sub/venv"] = true })
      local r = resolve.resolve({ root = root, cwd = dir .. "/sub", path = bare_path() })

      assert.equals(dir .. "/sub/venv", r.prefix)
    end)

    it("prefers .python-version over a project .venv", function()
      local r = resolve.resolve({
        root = root,
        cwd = fx.project({ [".python-version"] = "3.12.4\n", [".venv"] = true }),
        path = bare_path(),
      })
      assert.equals("3.12.4", r.version)
      assert.equals("local", r.origin)
    end)

    it("falls back to the global version", function()
      local r = resolve.resolve({ root = root, cwd = fx.project(), path = bare_path() })
      assert.equals("3.11.9", r.version)
      assert.equals("global", r.origin)
      assert.equals(root .. "/version", r.origin_file)
    end)

    it("falls back to system when nothing else applies", function()
      local bare = fx.pyenv_root({ versions = { "3.12.4" } }) -- no global version file
      local r = resolve.resolve({ root = bare, cwd = fx.project(), path = bare_path() })
      assert.equals("system", r.version)
      assert.equals("system", r.origin)
      assert.equals("system", r.kind)
    end)

    it("honours a caller-supplied resolution order", function()
      local r = resolve.resolve({
        root = root,
        cwd = fx.project({ [".python-version"] = "3.12.4\n" }),
        path = bare_path(),
        order = { "global", "local" }, -- global deliberately first
      })
      assert.equals("3.11.9", r.version)
      assert.equals("global", r.origin)
    end)
  end)

  describe(".python-version parsing", function()
    it("walks up parent directories to find the nearest file", function()
      local proj = fx.project({ [".python-version"] = "3.12.4\n" })
      vim.fn.mkdir(proj .. "/src/deep/nested", "p")

      local r =
        resolve.resolve({ root = root, cwd = proj .. "/src/deep/nested", path = bare_path() })
      assert.equals("3.12.4", r.version)
      assert.equals(proj .. "/.python-version", r.origin_file)
    end)

    it("uses the nearest file when several are nested", function()
      local proj = fx.project({
        [".python-version"] = "3.11.9\n",
        ["sub/.python-version"] = "3.12.4\n",
      })
      local r = resolve.resolve({ root = root, cwd = proj .. "/sub", path = bare_path() })
      assert.equals("3.12.4", r.version)
    end)

    it("ignores comments and blank lines", function()
      local r = resolve.resolve({
        root = root,
        cwd = fx.project({ [".python-version"] = "# a comment\n\n   \n3.12.4\n" }),
        path = bare_path(),
      })
      assert.equals("3.12.4", r.version)
    end)

    it("takes the first version when several are listed", function()
      local r = resolve.resolve({
        root = root,
        cwd = fx.project({ [".python-version"] = "3.12.4\n3.11.9\n" }),
        path = bare_path(),
      })
      assert.equals("3.12.4", r.version)
    end)

    it("skips a file containing only comments", function()
      local r = resolve.resolve({
        root = root,
        cwd = fx.project({ [".python-version"] = "# nothing here\n" }),
        path = bare_path(),
      })
      assert.equals("global", r.origin)
    end)

    it("trims surrounding whitespace", function()
      local r = resolve.resolve({
        root = root,
        cwd = fx.project({ [".python-version"] = "  3.12.4  \n" }),
        path = bare_path(),
      })
      assert.equals("3.12.4", r.version)
    end)
  end)

  describe("uninstalled versions", function()
    it("reports a requested-but-missing version instead of silently falling through", function()
      -- Falling back to system python here is exactly the confusing behaviour
      -- this plugin exists to eliminate.
      local r = resolve.resolve({
        root = root,
        cwd = fx.project({ [".python-version"] = "3.13.0\n" }),
        path = bare_path(),
      })
      assert.equals("3.13.0", r.version)
      assert.equals("local", r.origin)
      assert.is_true(r.missing)
    end)

    it("does not mark installed versions as missing", function()
      local r = resolve.resolve({
        root = root,
        cwd = fx.project({ [".python-version"] = "3.12.4\n" }),
        path = bare_path(),
      })
      assert.is_falsy(r.missing)
    end)
  end)

  describe("interpreter paths", function()
    it("never returns a shim path", function()
      local r = resolve.resolve({
        root = root,
        cwd = fx.project({ [".python-version"] = "3.12.4\n" }),
        path = root .. "/shims:/usr/bin:/bin",
      })
      assert.is_nil(r.python:match("/shims/"))
      assert.equals(root .. "/versions/3.12.4/bin/python", r.python)
    end)

    it("excludes the shims directory when resolving system python", function()
      local bare = fx.pyenv_root({})
      local r = resolve.resolve({
        root = bare,
        cwd = fx.project(),
        path = bare .. "/shims:/usr/bin:/bin",
      })
      assert.equals("system", r.origin)
      assert.is_nil((r.python or ""):match("/shims/"))
    end)

    it("resolves a virtualenv to its real interpreter", function()
      local r = resolve.resolve({
        root = root,
        cwd = fx.project({ [".python-version"] = "proj-env\n" }),
        path = bare_path(),
      })
      assert.equals("virtualenv", r.kind)
      assert.equals(root .. "/versions/3.12.4/envs/proj-env/bin/python", r.python)
      assert.equals("3.12.4", r.parent)
    end)
  end)

  describe("the literal version 'system'", function()
    it("resolves to system python rather than a versions/ directory", function()
      local r = resolve.resolve({
        root = root,
        cwd = fx.project({ [".python-version"] = "system\n" }),
        path = bare_path(),
      })
      assert.equals("system", r.version)
      assert.equals("system", r.kind)
      assert.equals("local", r.origin) -- origin is still the file that asked for it
      assert.is_falsy(r.missing)
    end)
  end)
end)
