local fx = require("fixtures")
local envs = require("pyenv.envs")

describe("pyenv.envs", function()
  after_each(function()
    fx.cleanup()
  end)

  describe("list", function()
    it("returns nothing for a root that does not exist", function()
      assert.same({}, envs.list("/nonexistent/pyenv/root"))
    end)

    it("returns nothing for a root with no versions installed", function()
      assert.same({}, envs.list(fx.pyenv_root()))
    end)

    it("lists plain installed versions", function()
      local root = fx.pyenv_root({ versions = { "3.11.9", "3.12.4" } })
      local list = envs.list(root)

      assert.equals(2, #list)
      assert.equals("3.11.9", list[1].name)
      assert.equals("version", list[1].kind)
      assert.equals(root .. "/versions/3.11.9", list[1].prefix)
      assert.equals(root .. "/versions/3.11.9/bin/python", list[1].python)
      assert.is_nil(list[1].parent)
    end)

    it("sorts versions numerically, not lexicographically", function()
      local root = fx.pyenv_root({ versions = { "3.9.1", "3.10.0", "3.12.4", "3.9.10" } })
      local names = vim.tbl_map(function(e)
        return e.name
      end, envs.list(root))

      -- "3.10.0" sorts before "3.9.1" as a string; that would be wrong.
      assert.same({ "3.9.1", "3.9.10", "3.10.0", "3.12.4" }, names)
    end)

    it("classifies a pyenv-virtualenv symlink as a virtualenv", function()
      local root = fx.pyenv_root({
        versions = { "3.12.4" },
        virtualenvs = { ["3.12.4"] = { "proj-env" } },
      })
      local list = envs.list(root)
      local by_name = {}
      for _, e in ipairs(list) do
        by_name[e.name] = e
      end

      local venv = by_name["proj-env"]
      assert.is_not_nil(venv)
      assert.equals("virtualenv", venv.kind)
      assert.equals("3.12.4", venv.parent)
      assert.equals("3.12.4/envs/proj-env", venv.qualified)
      assert.equals(root .. "/versions/3.12.4/envs/proj-env/bin/python", venv.python)
    end)

    it("reports each virtualenv once, not twice", function()
      -- pyenv-virtualenv creates two on-disk entries per virtualenv; a picker
      -- showing both would be confusing.
      local root = fx.pyenv_root({
        versions = { "3.12.4" },
        virtualenvs = { ["3.12.4"] = { "proj-env" } },
      })
      local seen = 0
      for _, e in ipairs(envs.list(root)) do
        if e.kind == "virtualenv" then
          seen = seen + 1
        end
      end
      assert.equals(1, seen)
    end)

    it("classifies a non-symlinked directory holding pyvenv.cfg as a virtualenv", function()
      local root = fx.pyenv_root({ versions = { "3.12.4" } })
      -- A venv created directly inside versions/ rather than by pyenv-virtualenv.
      local dir = root .. "/versions/manual-env"
      vim.fn.mkdir(dir .. "/bin", "p")
      vim.fn.writefile({ "version = 3.12.4" }, dir .. "/pyvenv.cfg")
      vim.fn.writefile({ "#!/bin/sh" }, dir .. "/bin/python")

      local kinds = {}
      for _, e in ipairs(envs.list(root)) do
        kinds[e.name] = e.kind
      end
      assert.equals("virtualenv", kinds["manual-env"])
      assert.equals("version", kinds["3.12.4"])
    end)

    it("ignores the shims directory", function()
      local root = fx.pyenv_root({ versions = { "3.12.4" } })
      for _, e in ipairs(envs.list(root)) do
        assert.not_equals("shims", e.name)
      end
    end)

    it("falls back to bin/python3 when bin/python is absent", function()
      local root = fx.pyenv_root({ versions = { "3.12.4" } })
      vim.fn.delete(root .. "/versions/3.12.4/bin/python")

      assert.equals(root .. "/versions/3.12.4/bin/python3", envs.list(root)[1].python)
    end)
  end)

  describe("find", function()
    it("finds an env by name", function()
      local root = fx.pyenv_root({
        versions = { "3.12.4" },
        virtualenvs = { ["3.12.4"] = { "proj-env" } },
      })
      assert.equals("version", envs.find(root, "3.12.4").kind)
      assert.equals("virtualenv", envs.find(root, "proj-env").kind)
    end)

    it("finds a virtualenv by its qualified name", function()
      local root = fx.pyenv_root({
        versions = { "3.12.4" },
        virtualenvs = { ["3.12.4"] = { "proj-env" } },
      })
      assert.equals("proj-env", envs.find(root, "3.12.4/envs/proj-env").name)
    end)

    it("returns nil for an unknown name", function()
      assert.is_nil(envs.find(fx.pyenv_root({ versions = { "3.12.4" } }), "nope"))
    end)
  end)
end)
