-- Entry point. Kept deliberately small: every `require` is deferred into a
-- callback so that loading this file costs almost nothing at startup.

if vim.g.loaded_pyenv then
  return
end
vim.g.loaded_pyenv = true

if vim.fn.has("nvim-0.11") == 0 then
  vim.notify(
    "pyenv.nvim requires Neovim 0.11 or newer (vim.lsp.config / vim.lsp.enable)",
    vim.log.levels.ERROR
  )
  return
end

vim.api.nvim_create_user_command("Pyenv", function(opts)
  require("pyenv.command").run(opts)
end, {
  nargs = "*",
  complete = function(arg_lead, cmd_line)
    return require("pyenv.command").complete(arg_lead, cmd_line)
  end,
  desc = "Manage pyenv environments",
})

-- <Plug> mappings only; binding keys is the user's decision.
vim.keymap.set("n", "<Plug>(pyenv-select)", function()
  require("pyenv.command").run({ fargs = { "select" } })
end, { desc = "pyenv: select environment" })

vim.keymap.set("n", "<Plug>(pyenv-reset)", function()
  require("pyenv.command").run({ fargs = { "reset" } })
end, { desc = "pyenv: reset environment" })

local group = vim.api.nvim_create_augroup("PyenvNvim", { clear = true })

---Resolve and wire up the environment for `cwd`. Scheduled so that startup is
---never blocked by filesystem work, and so that a `setup()` call made during
---plugin load has already been applied by the time this runs.
---@param cwd string?
local function activate(cwd)
  vim.schedule(function()
    if require("pyenv.config").get().auto_activate then
      require("pyenv").activate({ cwd = cwd })
    end
  end)
end

vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged" }, {
  group = group,
  desc = "Resolve the active pyenv environment for the current directory",
  callback = function(event)
    activate(event.event == "DirChanged" and vim.v.event.cwd or nil)
  end,
})

-- If this file is sourced after startup has finished -- a lazy-loaded plugin,
-- `:Lazy reload`, or a plain `require` from the command line -- then VimEnter
-- has already fired and will never fire again, so the autocmd above would leave
-- the plugin permanently inactive. Resolve straight away instead.
if vim.v.vim_did_enter == 1 then
  activate(nil)
end
