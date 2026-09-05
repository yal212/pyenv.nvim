-- Neovim config for the demo recordings.
--
--     nvim --clean -u demo/init.lua
--
-- Deliberately dependency-free, so the GIFs show this plugin rather than
-- somebody's dotfiles: a bundled colorscheme, the built-in statusline, and
-- `vim.ui.select`'s own prompt. What you see in the recording is what a bare
-- `opts = {}` install gives you.

local repo = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(repo)

-- $PYENV_ROOT comes from the tape's shell, so the same config records both the
-- tour (a populated root) and the install (an empty one).

-- catppuccin is bundled from 0.12; habamax goes back far enough for anyone
-- re-recording on the 0.11 this plugin still supports.
if not pcall(vim.cmd.colorscheme, "catppuccin") then
  vim.cmd.colorscheme("habamax")
end

vim.o.number = true
vim.o.signcolumn = "no"
vim.o.swapfile = false
vim.o.fillchars = "eob: "
vim.o.laststatus = 3
vim.o.shortmess = vim.o.shortmess .. "I"

-- `:Pyenv status` prints four lines. Without the room it would land on a
-- hit-enter prompt, and the recording would be of that prompt.
vim.o.cmdheight = 5

function _G.PyenvDemoStatus()
  return require("pyenv.statusline").status({ prefix = "py:" })
end

vim.o.statusline = "  %f %m%=%{v:lua.PyenvDemoStatus()}  "

-- Resolution is deferred (a scheduled callback on VimEnter and DirChanged) and
-- nothing is emitted when it lands, so a plain 'statusline' renders once while
-- there is still nothing to show and then sits stale until the next redraw.
-- lualine's own refresh timer hides this; a hand-rolled statusline has to nudge
-- it. Not needed for the plugin to work -- only for the first frame to be true.
vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged" }, {
  desc = "Redraw the statusline once pyenv.nvim has resolved",
  callback = function()
    vim.defer_fn(function()
      vim.cmd("redrawstatus")
    end, 300)
  end,
})
