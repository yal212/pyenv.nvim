# pyenv.nvim

pyenv integration for Neovim. Works out which Python is active for the directory
you're in, points your LSP, debugger and terminals at it, and lets you install
versions and create virtualenvs without leaving the editor.

No plugin dependencies. The picker uses `vim.ui.select`, so it adopts whichever
picker you already have.

## Why

Existing plugins switch *between* environments. None of them manage pyenv:

| | switch | pyenv-aware resolution | `pyenv install` | explains its choice |
|---|:---:|:---:|:---:|:---:|
| `venv-selector.nvim` | ✅ | partial (regex search) | ❌ | ❌ |
| `venv-lsp.nvim` | ✅ | ❌ | ❌ | ❌ |
| `swenv.nvim` | ✅ | ❌ | ❌ | ❌ |
| **pyenv.nvim** | ✅ | ✅ | ✅ | ✅ |

The last column matters more than it sounds. "Pyright is using the wrong Python"
is a common and near-undebuggable complaint; `:checkhealth pyenv` answers it
directly.

## Requirements

- Neovim 0.11+ (`vim.lsp.config` / `vim.lsp.enable`)
- pyenv — only for *installing* and *removing*. Listing and switching read
  `$PYENV_ROOT` from disk and work even when `pyenv` isn't on Neovim's `PATH`,
  which is routine for GUI launches on macOS.

## Install

```lua
-- lazy.nvim
{ "yal212/pyenv.nvim", opts = {} }
```

`setup()` is optional; the plugin initialises itself with sensible defaults.

## Use

```vim
:Pyenv                          " status: what's active, and why
:Pyenv select                   " pick an environment
:Pyenv install 3.13.2           " streamed into a floating window, cancellable
:Pyenv install --refresh        " re-read the list of installable versions
:Pyenv virtualenv 3.12.4 myapp  " create and activate
:checkhealth pyenv              " diagnose
```

Everything lives under one command with completion. No keys are bound; two
`<Plug>` mappings are provided:

```lua
vim.keymap.set("n", "<leader>pv", "<Plug>(pyenv-select)")
vim.keymap.set("n", "<leader>pr", "<Plug>(pyenv-reset)")
```

## How the environment is chosen

First match wins:

1. `override` — pinned with `:Pyenv activate`
2. `shell` — `$PYENV_VERSION`
3. `local` — nearest `.python-version`, searching upward
4. `project_venv` — `.venv/`, `venv/`, or `$VIRTUAL_ENV`
5. `global` — `$PYENV_ROOT/version`
6. `system` — first python on `PATH` outside pyenv's shims

Two deliberate departures from pyenv itself:

- **A project `.venv` outranks the global pyenv version.** A global version is a
  machine-wide default; a `.venv` belongs to the code in front of you. An
  explicit `.python-version` still beats both. Reorder via `resolution_order`.
- **A version named but not installed is reported, not silently replaced.**
  Falling back to system python is exactly the failure this plugin exists to
  prevent, so nothing is wired up and you get told.

Shims are never used as an interpreter — `$PYENV_ROOT/shims/python` is a shell
script that pyright can't introspect and debugpy can't exec.

## Configuration

```lua
require("pyenv").setup({
  root = nil,                 -- override $PYENV_ROOT
  auto_activate = true,       -- re-resolve on VimEnter and DirChanged
  resolution_order = { "override", "shell", "local", "project_venv", "global", "system" },
  lsp = { enabled = true, servers = { "pyright", "basedpyright", "pylsp" } },
  dap = { enabled = true },
  terminal = { set_path = true, set_virtual_env = true },
  python3_host_prog = false,  -- an env without pynvim breaks remote plugins
  notify = "changes",         -- "all" | "changes" | "errors" | false
  cache = { enabled = true },
})
```

Unknown options and wrong types are rejected with an explicit error.

`:Pyenv activate` is remembered per project in `stdpath("data")` — nothing is
written into your repository. Use `:Pyenv local` when you actually want a
committed `.python-version`.

### Language servers

pylsp is **updated in place** with a `didChangeConfiguration` notification.
pyright and basedpyright are **restarted**: a notification carries settings and
nothing else, while a restart also relaunches the server under the new
environment, and it holds for server versions that ignore the notification.
Restarts inside a short window are coalesced so rapid directory changes don't
thrash the server.

ruff isn't supported: its `interpreter` setting is a VS Code extension option
for locating the ruff binary, not a language server setting.

### Statusline

```lua
require("lualine").setup({
  sections = { lualine_x = { require("pyenv.statusline").lualine() } },
})
```

## Migrating from a hand-rolled `before_init`

If your LSP config picks the interpreter itself, remove it — it runs at client
init and will overwrite what this plugin sets. `:checkhealth pyenv` reports the
conflict as an error if you forget.

```lua
vim.lsp.config("pyright", {
  settings = { python = { analysis = { ... } } },
  -- before_init = function(params, config) ... end,   ← delete this
})
```

## Development

```sh
make deps    # busted + nlua into a local Lua 5.1 tree
make check   # stylua --check, luacheck, busted
```

Tests run under LuaJIT *inside* Neovim via `nlua`; Homebrew's `busted` runs on
Lua 5.4 where the `vim` global doesn't exist. Fixtures build real directories
and real symlinks, because pyenv-virtualenv classification depends on genuine
symlink behaviour that a mocked filesystem wouldn't reproduce. No pyenv install
is needed to run the suite.

## License

MIT
