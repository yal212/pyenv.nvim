local dap_integration = require("pyenv.integrations.dap")

local function resolution(extra)
  return vim.tbl_extend("force", {
    version = "3.12.4",
    kind = "version",
    python = "/pyenv/versions/3.12.4/bin/python",
    prefix = "/pyenv/versions/3.12.4",
  }, extra or {})
end

---Build a `require` that resolves only the named modules.
local function requiring(modules)
  return function(name)
    if modules[name] then
      return modules[name]
    end
    error("module '" .. name .. "' not found", 0)
  end
end

describe("pyenv.integrations.dap", function()
  it("prefers nvim-dap-python when it is available", function()
    local got
    local result = dap_integration.apply(resolution(), {
      require = requiring({
        ["dap-python"] = {
          setup = function(python)
            got = python
          end,
        },
      }),
    })

    assert.equals("dap-python", result)
    assert.equals("/pyenv/versions/3.12.4/bin/python", got)
  end)

  it("registers the adapter directly when only nvim-dap is available", function()
    local dap = { adapters = {} }
    local result = dap_integration.apply(resolution(), { require = requiring({ dap = dap }) })

    assert.equals("dap", result)
    assert.equals("executable", dap.adapters.python.type)
    assert.equals("/pyenv/versions/3.12.4/bin/python", dap.adapters.python.command)
    assert.same({ "-m", "debugpy.adapter" }, dap.adapters.python.args)
  end)

  it("does nothing when neither plugin is installed", function()
    assert.is_nil(dap_integration.apply(resolution(), { require = requiring({}) }))
  end)

  it("does not wire a version that is not installed", function()
    local dap = { adapters = {} }
    local result =
      dap_integration.apply(resolution({ missing = true }), { require = requiring({ dap = dap }) })
    assert.is_nil(result)
    assert.is_nil(dap.adapters.python)
  end)

  it("does not wire an environment with no interpreter", function()
    -- Built explicitly rather than via tbl_extend: assigning nil to a key does
    -- not remove it, so `python` would survive from the base table.
    local dap = { adapters = {} }
    local without_python = { version = "system", kind = "system" }

    assert.is_nil(dap_integration.apply(without_python, { require = requiring({ dap = dap }) }))
    assert.is_nil(dap.adapters.python)
  end)
end)
