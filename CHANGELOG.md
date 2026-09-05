# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Nothing has been released yet. Changes accumulate here until the first tagged
version.

### Fixed

- `notify` is checked by value, not only by type. A misspelling no longer falls
  through to the noisiest setting - most importantly `notify = "false"`, the
  string rather than the boolean, which asked for silence and produced a
  notification on every resolution. `notify = true` is accepted as `"all"`.
- `g:python3_host_prog` is reverted when the environment stops being usable,
  instead of being left pointing at the previous project's interpreter while
  `PATH`, `$PYENV_VERSION` and `$VIRTUAL_ENV` have all released it. A value the
  user set before the plugin loaded is restored rather than cleared.
- The test suite passes on machines that have pyenv installed. `cli.run` read
  its injected `binary` seam with `or`, so a spec injecting `false` for "there
  is no pyenv" got the real lookup instead - and on a machine with pyenv, ran
  it. CI never caught it: GitHub runners have no pyenv.
- `doc/pyenv.txt` no longer defines a stray `global` help tag. Vimdoc parses
  `*word*` as a tag definition rather than as emphasis, so the plugin was
  claiming `:help global` in Neovim's shared help namespace.

### Changed

- README reorganised around reference material: full command table, complete
  Lua API, configuration option table, and installation instructions for
  rocks.nvim, mini.deps, packer and vim-plug alongside lazy.nvim.
- The design document moved from `docs/superpowers/specs/` to `docs/design.md`.

### Added

- `CONTRIBUTING.md`, covering the `nlua` test toolchain and the vimdoc rules.
- Vimdoc now documents `require("pyenv").setup()`, the `pyenv.Resolution` and
  `pyenv.Env` type shapes, the per-project cache location, and the optional
  nvim-dap / `vim.ui.select` / lualine integrations.

[Unreleased]: https://github.com/yal212/pyenv.nvim/commits/main
