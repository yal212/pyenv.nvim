local progress = require("pyenv.ui.progress")

describe("pyenv.ui.progress", function()
  local handle

  after_each(function()
    if handle then
      handle.close()
      handle = nil
    end
  end)

  local function lines()
    return vim.api.nvim_buf_get_lines(handle.buf, 0, -1, false)
  end

  it("opens a floating window with a scratch buffer", function()
    handle = progress.open("pyenv install 3.12.4")
    assert.is_true(vim.api.nvim_win_is_valid(handle.win))
    assert.equals("editor", vim.api.nvim_win_get_config(handle.win).relative)
    assert.equals("pyenv-progress", vim.bo[handle.buf].filetype)
  end)

  it("writes the first line over the buffer's initial blank line", function()
    handle = progress.open("test")
    handle.append("downloading...")
    assert.same({ "downloading..." }, lines())
  end)

  it("appends subsequent lines", function()
    handle = progress.open("test")
    handle.append("one")
    handle.append("two")
    assert.same({ "one", "two" }, lines())
  end)

  it("marks a successful run as done", function()
    handle = progress.open("test")
    handle.append("building")
    handle.finish(0)
    assert.is_truthy(lines()[#lines()]:match("done"))
  end)

  it("shows the exit code when the run fails", function()
    handle = progress.open("test")
    handle.finish(2)
    assert.is_truthy(lines()[#lines()]:match("failed %(exit 2%)"))
  end)

  it("leaves focus where the user put it when the run finishes", function()
    -- Regression guard. `pyenv install` runs for minutes; by the time it lands
    -- the user is typing in another buffer, and this window maps `q` to close.
    local before = vim.api.nvim_get_current_win()
    handle = progress.open("test")
    handle.finish(0)

    assert.equals(before, vim.api.nvim_get_current_win())
  end)

  it("leaves focus alone on failure too", function()
    local before = vim.api.nvim_get_current_win()
    handle = progress.open("test")
    handle.finish(2)

    assert.equals(before, vim.api.nvim_get_current_win())
  end)

  it("cancels when the window is closed with q", function()
    local cancelled = false
    handle = progress.open("test", function()
      cancelled = true
    end)
    vim.api.nvim_set_current_win(handle.win)
    vim.api.nvim_feedkeys("q", "x", false)

    assert.is_true(cancelled)
  end)

  it("survives being closed twice", function()
    handle = progress.open("test")
    handle.close()
    assert.has_no.errors(handle.close)
  end)
end)
