# Contributing to pyenv.nvim

Thanks for taking the time. This file covers the development setup and the few
things about this repository that are genuinely surprising.

## Setup

The test toolchain installs into `./.luarocks`, which is gitignored - nothing is
written outside the repository.

```sh
make deps    # busted + nlua into a local Lua 5.1 tree
make check   # stylua --check, luacheck, busted
```

`make check` is what CI runs. The individual targets are `make fmt` (check
formatting), `make fmt-fix` (apply it), `make lint`, and `make test`. Pass extra
busted arguments through `BUSTED_ARGS`:

```sh
make test BUSTED_ARGS="--filter=resolution"
```

**The suite passes with or without pyenv installed**, and needs neither. That
is deliberate - see below. It held in one direction only until #24: a real
pyenv on `PATH` used to win over a test's injected "there is no pyenv", so the
suite was red for exactly the contributors most likely to be working on it.

## Why the toolchain looks unusual

Three things here will look wrong if you don't know why they are that way.

**Tests run inside Neovim, via `nlua`.** The code under test uses the `vim`
global throughout, so the tests need Lua 5.1/LuaJIT *with Neovim's runtime
present*. `busted --lua=nlua` re-executes busted inside Neovim to get that. If
you have Homebrew's `busted` on your `PATH`, it runs on Lua 5.4 where `vim` does
not exist - it is the wrong tool for this repository and the Makefile
deliberately does not use it.

**`make test` closes stdin.** The recipe ends in `< /dev/null` because `nlua`
drops into a REPL on a non-tty stdin and would otherwise hang forever.

**CI's luarocks host is PUC Lua 5.1, not LuaJIT.** The luarocks.org manifest
exceeds LuaJIT's 65536-constant bytecode limit and fails to load. Rocks still
target 5.1, and the tests themselves still run inside Neovim's LuaJIT, because
busted is re-executed through `nlua`.

## Tests

Fixtures build **real** temporary directory trees, including real symlinks,
rather than mocking the filesystem. This is not incidental: pyenv-virtualenv
stores the real directory at `$PYENV_ROOT/versions/<py>/envs/<name>` and a
symlink at `$PYENV_ROOT/versions/<name>`, so classification depends on genuine
symlink behaviour that a mocked filesystem would not reproduce.

Pure logic is kept separate from side effects so the core is testable with no
pyenv installed - `resolve` and `envs` take an injected root and cwd and touch
nothing else, and `cli` takes an injectable runner so mutating commands are
asserted on their argv without spawning anything. Please keep new code on the
same side of that line.

## Style and linting

- `stylua` over `lua plugin spec` - config in `stylua.toml` (2-space indent,
  100-column width, double quotes preferred).
- `luacheck` over `lua plugin spec` - config in `.luacheckrc` (LuaJIT std, `vim`
  global, 120-column max).

Both run in CI and both must pass.

## CI

Two jobs, in `.github/workflows/ci.yml`:

- **test** - the suite against Neovim `v0.11.0`, `stable` and `nightly`.
  `v0.11.0` is the floor the plugin claims, so it is tested explicitly.
- **lint** - `stylua --check` and `luacheck`.

## Documentation

User-facing behaviour is documented twice, and both need to stay in step:

- `README.md` - the entry point.
- `doc/pyenv.txt` - the vimdoc, which is the reference.

Two rules for the vimdoc:

- **Keep every line at 78 columns or fewer**, matching the file's own
  `vim:tw=78` modeline. Check with:
  ```sh
  awk 'length > 78 {print FILENAME":"NR": "length}' doc/pyenv.txt
  ```
- **Never write `*word*` for emphasis.** Vimdoc parses it as a *tag definition*,
  which leaks into the user's global help namespace - this repository shipped a
  stray `global` tag that way. Every tag defined here must start with `pyenv` or
  `:Pyenv`. Check with:
  ```sh
  nvim --headless -c 'helptags doc' -c q && grep -vE '^(pyenv|:Pyenv)' doc/tags
  ```

`doc/tags` is generated and gitignored; don't commit it.

The two GIFs in the README are generated too - `make demo` records them against
a real pyenv installation rather than a fixture. Anything that changes what the
plugin puts on screen dates them; [`demo/README.md`](demo/README.md) covers
re-recording and what to check when you do.

## Architecture

[`docs/design.md`](docs/design.md) records the module boundaries and the
reasoning behind the design decisions, including the ones that were later
revised. Read it before changing resolution or the LSP integration.
