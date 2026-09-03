--- Statusline helpers.
---
--- These only read cached state, so they are safe to call on every redraw.
local M = {}

local pyenv = require("pyenv")

---@class pyenv.StatuslineOpts
---@field icon   string? prefix, e.g. a Nerd Font glyph. No icon by default,
---              since not everyone has a patched font.
---@field prefix string? plain text prefix, e.g. "py:"

---A short description of the active environment, or "" when there is none.
---@param opts pyenv.StatuslineOpts?
---@return string
function M.status(opts)
  opts = opts or {}
  local text = pyenv.status()
  if text == "" then
    return ""
  end
  local prefix = opts.icon or opts.prefix
  return prefix and (prefix .. " " .. text) or text
end

---A lualine component.
---
---    require("lualine").setup({
---      sections = { lualine_x = { require("pyenv.statusline").lualine() } },
---    })
---@param opts pyenv.StatuslineOpts?
---@return table
function M.lualine(opts)
  return {
    function()
      return M.status(opts)
    end,
    cond = function()
      return pyenv.status() ~= ""
    end,
  }
end

return M
