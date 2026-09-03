-- Guards the test harness itself: these tests must run inside Neovim's LuaJIT
-- (via nlua), not the system Lua 5.4, or every `vim.*` call below is a lie.
describe("test harness", function()
  it("runs on Lua 5.1 / LuaJIT", function()
    assert.equals("Lua 5.1", _VERSION)
    assert.is_truthy(jit)
  end)

  it("exposes the vim global", function()
    assert.equals("table", type(vim))
    assert.equals("function", type(vim.system))
    assert.equals("function", type(vim.fs.parents))
    assert.equals("table", type(vim.uv))
  end)

  it("can create and remove real files", function()
    local dir = vim.fs.joinpath(vim.uv.os_tmpdir(), "pyenv_nvim_harness_check")
    vim.fn.mkdir(dir, "p")
    assert.equals(1, vim.fn.isdirectory(dir))
    vim.fn.delete(dir, "rf")
    assert.equals(0, vim.fn.isdirectory(dir))
  end)
end)
