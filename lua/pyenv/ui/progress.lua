--- A floating window that streams the output of a long-running pyenv command.
---
--- `pyenv install` compiles CPython from source and takes minutes, so its
--- output has to go somewhere visible and it has to stay cancellable.
local M = {}

---@class pyenv.Progress
---@field append fun(line: string)
---@field finish fun(code: integer)
---@field close  fun()

---@param title string
---@param on_cancel fun()?
---@return pyenv.Progress
function M.open(title, on_cancel)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "pyenv-progress"

  local width = math.min(100, math.max(60, math.floor(vim.o.columns * 0.7)))
  local height = math.min(24, math.max(10, math.floor(vim.o.lines * 0.5)))

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "center",
  })
  vim.wo[win].wrap = false

  local closed = false
  local function close()
    if closed then
      return
    end
    closed = true
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function append(line)
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local last = vim.api.nvim_buf_line_count(buf)
    -- A freshly created scratch buffer has one empty line; write over it.
    local first = (last == 1 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "") and 0
      or last
    vim.api.nvim_buf_set_lines(buf, first, -1, false, { line })
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
    end
  end

  vim.keymap.set("n", "q", function()
    if on_cancel then
      on_cancel()
    end
    close()
  end, { buffer = buf, nowait = true, desc = "close (cancels if still running)" })

  local function finish(code)
    append("")
    append(
      code == 0 and "-- done. press q to close --"
        or ("-- failed (exit %d). press q to close --"):format(code)
    )
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_set_current_win(win)
    end
  end

  return { append = append, finish = finish, close = close, buf = buf, win = win }
end

return M
