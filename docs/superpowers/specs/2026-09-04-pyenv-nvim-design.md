# pyenv.nvim — design

Status: accepted, 2026-09-04

## Problem

pyenv is a first-class tool for most Python developers and a second-class citizen in Neovim.
No maintained Lua plugin *manages* pyenv. The adjacent plugins are generic virtualenv
switchers:

| Plugin | What it does | Gap |
|---|---|---|
| `venv-selector.nvim` | Generic venv switcher, hot-swap, dap/statusline hooks | telescope + fd dependencies; pyenv is one regex "search"; cannot install versions |
| `venv-lsp.nvim` | Auto-activates a venv for LSP | Narrow; no management, no UI |
| `swenv.nvim` | Lists and picks envs | Narrow; unmaintained-ish |
| `vim-pyenv` | pyenv for Vim's `+python` host | 2015-era Vimscript; irrelevant to Neovim LSP |

None of them can run `pyenv install`, create a `pyenv virtualenv`, or explain *why* a given
interpreter was chosen. That last point matters more than it sounds: "pyright is using the
wrong Python" is one of the most common and least debuggable Neovim complaints.

## Goals

1. **Auto-wire** — the active pyenv environment drives pyright/basedpyright/pylsp/ruff,
   nvim-dap, `:terminal`, and `:!python`, with no manual step.
2. **Switch** — a dependency-free picker over installed versions and pyenv-virtualenvs that
   hot-swaps the LSP without restarting Neovim.
3. **Manage** — `pyenv install` / `uninstall` / `virtualenv` from inside Neovim, async.
4. **Explain** — `:checkhealth pyenv` answers "which Python is active, why, and did the LSP
   actually get it?"

## Non-goals

- Replacing venv-selector for conda/poetry/hatch. The `.venv` fallback exists only so the
  plugin can own interpreter selection outright without regressing non-pyenv projects.
- Managing pyenv's shell integration. We read pyenv's state; we never edit the user's shell rc.
- Bundling a picker. `vim.ui.select` inherits whatever the user already has.

## Key decisions

### D1 — Filesystem-first, subprocess only for mutations

Queries (which version is active, which are installed) are pure filesystem reads of
`$PYENV_ROOT`. The `pyenv` binary is invoked only for state-changing operations.

*Why:* `pyenv versions` costs a bash spawn plus a rehash — 50-150ms, on a `DirChanged` hot
path. A directory read is ~1ms. More importantly, GUI-launched Neovim on macOS frequently has
no `pyenv` on `PATH` at all, and a subprocess-based design is simply broken there, while a
filesystem-based one works fine.

*Cost:* we reimplement pyenv's resolution rules. Mitigated by D6.

### D2 — Resolution order diverges from pyenv, deliberately

```
override → shell (PYENV_VERSION) → local (.python-version) → project venv → global → system
```

pyenv itself has no "project venv" step and would place `global` fourth. We rank a
project-local `.venv`/`venv` *above* the global pyenv version because a global version is a
machine-wide default while a `.venv` is project-scoped. `.python-version` still beats both, so
an explicit pyenv declaration always wins. Configurable via `resolution_order`.

### D3 — Never hand out a shim path

`$PYENV_ROOT/shims/python` is a bash script. Pyright cannot introspect it, and debugpy cannot
exec it as an adapter host. Resolution always terminates at a real
`$PYENV_ROOT/versions/<v>/bin/python`.

### D4 — Restart LSP clients; don't rely on `didChangeConfiguration`

`vim.lsp.config(name, cfg)` sits at the highest merge priority (`:h lsp-config-merge`), so
writing there fixes all *future* client starts. Running clients need more: pyright does not
reliably re-read `python.pythonPath` from a `workspace/didChangeConfiguration` notification.
venv-selector reaches for an explicit restart gate for the same reason.

There is no `vim.lsp.restart()`. Restart is `vim.lsp.enable(name, false)` followed by
`vim.lsp.enable(name)`, with a fallback to `Client:stop()` + `vim.lsp.start()` per attached
buffer for clients not governed by `vim.lsp.enable`.

Restarts are **coalesced** behind a short timer so a burst of `DirChanged` events causes one
restart, not five.

> **Measured 2026-09-05 (#3, #4).** The premise above is wrong for current versions: pyright
> 1.1.412 and basedpyright 1.39.10 both *do* act on `workspace/didChangeConfiguration` — driven
> through the notify path alone, a running client stopped resolving the old environment's
> packages and started resolving the new one's, with no restart. The restart is kept anyway,
> because it also relaunches the server under the new `cmd_env` and holds for versions that have
> not been measured, but it is no longer justified by the servers being unable to reload.

### D5 — Per-project cache, never write to the user's repo

A manual pick is remembered in `stdpath("data")` keyed by project root. Writing
`.python-version` is a separate, explicit `:Pyenv local` — creating a tracked file in
someone's repo as a side effect of picking from a menu is a surprise, not a feature.

### D6 — Health check cross-verifies against the real pyenv

Because D1 means we reimplement resolution, `:checkhealth pyenv` compares our answer to
`pyenv version-name` whenever the binary exists. A divergence surfaces as a warning rather
than as silent wrongness.

## On-disk facts this design depends on

- Resolution: `PYENV_VERSION` → nearest `.python-version` walking up to `/` →
  `$PYENV_ROOT/version` → `system`.
- `.python-version` may contain multiple newline-separated versions; `#` lines are comments.
- `system` means the first `python` on `PATH` *after* the shims entry.
- pyenv-virtualenv stores the real directory at `$PYENV_ROOT/versions/<py>/envs/<name>` and a
  **symlink** at `$PYENV_ROOT/versions/<name>`. An entry in `versions/` is therefore a
  virtualenv if it is a symlink or contains `pyvenv.cfg`.

## Module boundaries

Pure logic is separated from side effects so the core is testable with no pyenv installed.

| Module | Purpose | Side effects |
|---|---|---|
| `root` | Locate `PYENV_ROOT` and the `pyenv` binary | reads env/fs |
| `resolve` | Resolution chain → `pyenv.Resolution` | **none** (injected root + cwd) |
| `envs` | Enumerate versions/virtualenvs | **none** (reads injected root) |
| `state` | Active env + per-project cache | reads/writes one JSON file |
| `cli` | Async `pyenv` subprocess | spawns; runner is injectable |
| `integrations/env` | `vim.env` PATH / PYENV_VERSION / VIRTUAL_ENV | mutates `vim.env` |
| `integrations/lsp` | Server adapter table + restart gate | mutates LSP config |
| `integrations/dap` | dap-python / dap adapter | mutates dap tables |
| `ui/select`, `ui/progress` | `vim.ui.select`; floating install log | UI |
| `command`, `health`, `statusline` | `:Pyenv`, `:checkhealth`, status string | UI |

## Testing strategy

Tests run under Lua 5.1/LuaJIT inside Neovim (busted re-executed via `nlua`), because the
system busted runs on Lua 5.4 where the `vim` global does not exist.

Fixtures build **real** temporary directory trees — including real symlinks — so virtualenv
classification is exercised rather than mocked. `cli` takes an injectable runner so mutation
commands are asserted on argv without spawning anything.

## Compatibility

Minimum Neovim **0.11** (`vim.lsp.config`, `vim.lsp.enable`). Developed against 0.12.
