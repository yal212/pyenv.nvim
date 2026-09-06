# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-09-06

First public release.

### Added

- **Resolution that follows pyenv's own rules.** The active environment is
  worked out from `:Pyenv activate` pins, `$PYENV_VERSION`, the nearest
  `.python-version`, a project `.venv`/`venv`/`$VIRTUAL_ENV`, the pyenv global
  version, and finally system Python - in that order, reordered or trimmed
  through `resolution_order`. Shims are never handed out as an interpreter.
- **The reason is reported, not just the answer.** Every resolution carries the
  step that decided it and the file that did so, which `:Pyenv status`, the
  statusline and `:checkhealth pyenv` all surface. A version that is named but
  not installed is reported as missing rather than silently replaced with
  system Python.
- **Language servers are updated in place.** pyright, basedpyright and pylsp are
  reconfigured with a `didChangeConfiguration` notification, so switching
  environments costs no re-index. `lsp.strategy = "restart"` relaunches them
  instead.
- **nvim-dap and terminals** follow the active environment: debugpy is pointed
  at the interpreter, and `PATH` and `$VIRTUAL_ENV` are exported to `:terminal`.
  `g:python3_host_prog` can opt in, and is reverted when the environment stops
  being usable.
- **`:Pyenv`**, one command with completion for its subcommands and their
  arguments: `status`, `select`, `activate`, `reset`, `local`, `global`,
  `install`, `uninstall`, `virtualenv`, `rehash` and `health`. `install`
  streams a real build into a floating window that never steals focus and can
  be cancelled; `uninstall` always confirms, defaulting to No.
- **Per-project pins** stored under `stdpath("data")` - nothing is written into
  your repository unless you ask for it with `:Pyenv local`.
- **`:checkhealth pyenv`**, which reports the pyenv root and how it was found,
  competing environment plugins, the active environment and the file that chose
  it, and - for each running Python language server - the interpreter it is
  really using versus the one that was resolved.
- **A statusline component** for lualine, plus a plain string for everything
  else, reading only cached state so it is safe on every redraw.
- **No plugin dependencies.** The picker goes through `vim.ui.select`, so it
  adopts whichever picker is already installed.

[Unreleased]: https://github.com/yal212/pyenv.nvim/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/yal212/pyenv.nvim/releases/tag/v1.0.0
