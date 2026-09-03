# pyenv.nvim development tasks.
#
# Tests must run under Lua 5.1/LuaJIT with the `vim` global available, so busted
# is re-executed inside Neovim via nlua. The system busted (Lua 5.4) is wrong for
# this and is deliberately not used.

LUA_DIR  := /opt/homebrew/opt/luajit
TREE     := .luarocks
LUAROCKS := luarocks --lua-version=5.1 --lua-dir=$(LUA_DIR) --tree=$(TREE)
SOURCES  := lua plugin spec

.PHONY: all deps test lint fmt fmt-fix check clean

all: check

## Install the Lua 5.1 test toolchain into ./.luarocks (gitignored).
deps:
	$(LUAROCKS) install busted
	$(LUAROCKS) install nlua

## Run the test suite. stdin is closed because nlua drops into a REPL on a
## non-tty stdin and would otherwise hang forever.
test:
	@eval "$$($(LUAROCKS) path)"; \
	export PATH="$(CURDIR)/$(TREE)/bin:$$PATH"; \
	$(TREE)/bin/busted --lua=nlua $(BUSTED_ARGS) < /dev/null

lint:
	luacheck $(SOURCES)

fmt:
	stylua --check $(SOURCES)

fmt-fix:
	stylua $(SOURCES)

check: fmt lint test

clean:
	rm -rf $(TREE) luacov.*.out
