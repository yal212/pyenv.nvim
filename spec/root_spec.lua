local fx = require("fixtures")
local root_mod = require("pyenv.root")

describe("pyenv.root", function()
  after_each(function()
    fx.cleanup()
  end)

  describe("find", function()
    it("prefers an explicitly configured root", function()
      assert.equals("/opt/pyenv", root_mod.find({ configured = "/opt/pyenv", env = "/env/pyenv" }))
    end)

    it("expands ~ in a configured root", function()
      local found = root_mod.find({ configured = "~/custom-pyenv" })
      assert.equals(vim.fn.expand("~") .. "/custom-pyenv", found)
    end)

    it("uses $PYENV_ROOT when nothing is configured", function()
      assert.equals("/env/pyenv", root_mod.find({ env = "/env/pyenv" }))
    end)

    it("honours an explicit root even when it does not exist", function()
      -- pyenv itself respects $PYENV_ROOT unconditionally; health reports the
      -- problem rather than this silently picking somewhere else.
      assert.equals("/nope/pyenv", root_mod.find({ env = "/nope/pyenv" }))
    end)

    it("falls back to ~/.pyenv when it exists", function()
      local home = fx.tmpdir("home")
      vim.fn.mkdir(home .. "/.pyenv", "p")
      assert.equals(home .. "/.pyenv", root_mod.find({ home = home }))
    end)

    it("returns nil when there is no pyenv anywhere", function()
      assert.is_nil(root_mod.find({ home = fx.tmpdir("empty-home") }))
    end)

    it("ignores empty strings", function()
      assert.is_nil(root_mod.find({ configured = "", env = "", home = fx.tmpdir("h") }))
    end)
  end)

  describe("binary", function()
    it("prefers <root>/bin/pyenv over PATH", function()
      -- A git-cloned pyenv ships its own bin/. Finding it here means management
      -- commands still work when Neovim was launched without pyenv on PATH.
      local root = fx.pyenv_root({})
      vim.fn.mkdir(root .. "/bin", "p")
      vim.fn.writefile({ "#!/bin/sh" }, root .. "/bin/pyenv")
      vim.uv.fs_chmod(root .. "/bin/pyenv", tonumber("755", 8))

      assert.equals(root .. "/bin/pyenv", root_mod.binary(root, ""))
    end)

    it("finds pyenv on PATH when the root has no bin/", function()
      local dir = fx.tmpdir("bin")
      vim.fn.writefile({ "#!/bin/sh" }, dir .. "/pyenv")
      vim.uv.fs_chmod(dir .. "/pyenv", tonumber("755", 8))

      assert.equals(dir .. "/pyenv", root_mod.binary(fx.pyenv_root({}), dir))
    end)

    it("returns nil when pyenv is on neither the root nor PATH", function()
      assert.is_nil(root_mod.binary(fx.pyenv_root({}), "/nowhere:/also/nowhere"))
    end)

    it("tolerates a nil root", function()
      assert.has_no.errors(function()
        root_mod.binary(nil, "")
      end)
    end)
  end)
end)
