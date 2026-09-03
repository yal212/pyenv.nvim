local fx = require("fixtures")
local state = require("pyenv.state")

describe("pyenv.state", function()
  local cache

  before_each(function()
    cache = fx.tmpdir("state") .. "/projects.json"
    state.reset({ path = cache, enabled = true })
  end)

  after_each(function()
    state.reset()
    fx.cleanup()
  end)

  describe("overrides", function()
    it("returns nil for a project with no override", function()
      assert.is_nil(state.get_override("/some/project"))
    end)

    it("stores and reads back an override", function()
      state.set_override("/some/project", "proj-env")
      assert.equals("proj-env", state.get_override("/some/project"))
    end)

    it("keeps overrides separate per project", function()
      state.set_override("/a", "env-a")
      state.set_override("/b", "env-b")
      assert.equals("env-a", state.get_override("/a"))
      assert.equals("env-b", state.get_override("/b"))
    end)

    it("clears an override", function()
      state.set_override("/some/project", "proj-env")
      state.clear_override("/some/project")
      assert.is_nil(state.get_override("/some/project"))
    end)

    it("persists across a reload", function()
      state.set_override("/some/project", "proj-env")
      state.reset({ path = cache, enabled = true }) -- as if Neovim restarted
      assert.equals("proj-env", state.get_override("/some/project"))
    end)

    it("normalises project paths so a trailing slash is the same project", function()
      state.set_override("/some/project/", "proj-env")
      assert.equals("proj-env", state.get_override("/some/project"))
    end)
  end)

  describe("when caching is disabled", function()
    before_each(function()
      state.reset({ path = cache, enabled = false })
    end)

    it("keeps the override for the session but writes no file", function()
      state.set_override("/some/project", "proj-env")
      assert.equals("proj-env", state.get_override("/some/project"))
      assert.equals(0, vim.fn.filereadable(cache))
    end)

    it("does not restore overrides after a reload", function()
      state.set_override("/some/project", "proj-env")
      state.reset({ path = cache, enabled = false })
      assert.is_nil(state.get_override("/some/project"))
    end)
  end)

  describe("corrupt cache files", function()
    it("starts empty rather than erroring", function()
      vim.fn.mkdir(vim.fs.dirname(cache), "p")
      vim.fn.writefile({ "this is not json {{{" }, cache)

      assert.has_no.errors(function()
        state.reset({ path = cache, enabled = true })
      end)
      assert.is_nil(state.get_override("/some/project"))
    end)

    it("recovers by overwriting on the next write", function()
      vim.fn.mkdir(vim.fs.dirname(cache), "p")
      vim.fn.writefile({ "garbage" }, cache)
      state.reset({ path = cache, enabled = true })

      state.set_override("/some/project", "proj-env")
      state.reset({ path = cache, enabled = true })
      assert.equals("proj-env", state.get_override("/some/project"))
    end)

    it("ignores a JSON document that is not an object", function()
      vim.fn.mkdir(vim.fs.dirname(cache), "p")
      vim.fn.writefile({ "[1, 2, 3]" }, cache)

      assert.has_no.errors(function()
        state.reset({ path = cache, enabled = true })
      end)
      assert.is_nil(state.get_override("/x"))
    end)
  end)

  describe("current resolution", function()
    it("is nil before anything is activated", function()
      assert.is_nil(state.current())
    end)

    it("remembers the last activated resolution", function()
      local resolution = { version = "3.12.4", origin = "local", kind = "version" }
      state.set_current(resolution)
      assert.equals("3.12.4", state.current().version)
    end)

    it("is session-only and never written to the cache file", function()
      state.set_current({ version = "3.12.4", origin = "local", kind = "version" })
      state.reset({ path = cache, enabled = true })
      assert.is_nil(state.current())
    end)
  end)

  describe("project_root", function()
    it("finds the directory holding .python-version", function()
      local proj = fx.project({ [".python-version"] = "3.12.4\n" })
      vim.fn.mkdir(proj .. "/src/deep", "p")
      assert.equals(proj, state.project_root(proj .. "/src/deep"))
    end)

    it("finds the directory holding pyproject.toml", function()
      local proj = fx.project({ ["pyproject.toml"] = "[project]\n" })
      vim.fn.mkdir(proj .. "/src", "p")
      assert.equals(proj, state.project_root(proj .. "/src"))
    end)

    it("falls back to the given directory when no marker exists", function()
      local dir = fx.tmpdir("unmarked")
      assert.equals(dir, state.project_root(dir))
    end)
  end)
end)
