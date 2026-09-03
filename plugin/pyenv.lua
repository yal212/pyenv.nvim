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

vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged" }, {
  group = group,
  desc = "Resolve the active pyenv environment for the current directory",
  callback = function(event)
    if not require("pyenv.config").get().auto_activate then
      return
    end
    local cwd = event.event == "DirChanged" and vim.v.event.cwd or nil
    -- Scheduled so startup is never blocked by filesystem work.
    vim.schedule(function()
      require("pyenv").activate({ cwd = cwd })
    end)
  end,
})
