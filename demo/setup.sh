#!/usr/bin/env bash
#
# Build the world the demo recordings run against.
#
# Everything lives under $DEMO_HOME rather than your real home, because the
# resolution output that makes these GIFs worth recording puts absolute paths on
# screen -- filming against ~/.pyenv would bake a personal path into a public
# README.
#
# Idempotent: anything already built is left alone. The CPython builds are the
# slow part, several minutes apiece, and they are real -- nothing here stubs an
# interpreter. `demo/install.tape` deliberately gets a root of its own that
# `make demo` wipes first, so the install it films is always a genuine build
# from nothing rather than `pyenv install -s` returning instantly.
set -euo pipefail

DEMO_HOME="${DEMO_HOME:-/tmp/pyenv-demo}"
TOUR_ROOT="$DEMO_HOME/.pyenv"
API_VERSION="${API_VERSION:-3.12.4}"
SCRAPER_VERSION="${SCRAPER_VERSION:-3.13.2}"

command -v pyenv >/dev/null || {
  echo "demo/setup.sh: pyenv is not on PATH (brew install pyenv pyenv-virtualenv)" >&2
  exit 1
}
command -v pyenv-virtualenv >/dev/null || {
  echo "demo/setup.sh: pyenv-virtualenv is not installed (brew install pyenv-virtualenv)" >&2
  exit 1
}

export PYENV_ROOT="$TOUR_ROOT"
mkdir -p "$TOUR_ROOT"

# ---------------------------------------------------------------- interpreters

install_version() {
  if [ -x "$TOUR_ROOT/versions/$1/bin/python" ]; then
    echo "==> $1 already built"
  else
    echo "==> building $1 (this takes a few minutes)"
    pyenv install "$1"
  fi
}

make_virtualenv() {
  local version="$1" name="$2"
  if [ -x "$TOUR_ROOT/versions/$version/envs/$name/bin/python" ]; then
    echo "==> $name already created"
  else
    echo "==> creating $name from $version"
    pyenv virtualenv "$version" "$name"
  fi
}

install_version "$API_VERSION"
install_version "$SCRAPER_VERSION"
make_virtualenv "$API_VERSION" api-env
make_virtualenv "$SCRAPER_VERSION" scraper-env

# ------------------------------------------------------------------- projects
#
# Two projects that resolve by different steps, which is the whole point of the
# tour: `api` is pinned by a committed `.python-version`, `scraper` by a plain
# `.venv` that no pyenv file mentions at all.

api="$DEMO_HOME/code/api"
scraper="$DEMO_HOME/code/scraper"
mkdir -p "$api" "$scraper"

echo "api-env" > "$api/.python-version"
cat > "$api/app.py" <<'PY'
from fastapi import FastAPI

app = FastAPI()


@app.get("/healthz")
def healthz():
    return {"status": "ok"}
PY

cat > "$scraper/scrape.py" <<'PY'
import httpx


def fetch(url: str) -> str:
    return httpx.get(url, timeout=10).text
PY

if [ ! -x "$scraper/.venv/bin/python" ]; then
  echo "==> creating $scraper/.venv from $SCRAPER_VERSION"
  "$TOUR_ROOT/versions/$SCRAPER_VERSION/bin/python" -m venv "$scraper/.venv"
fi

# A directory with no version markers at all, for install.tape: it films a
# root where nothing is installed yet, and a project pinned to a missing
# version would open on an error rather than on the install.
lab="$DEMO_HOME/code/lab"
mkdir -p "$lab"
cat > "$lab/main.py" <<'PY'
def main() -> None:
    print("hello from the demo")


if __name__ == "__main__":
    main()
PY

# git repos so `project_root` stops here rather than walking up into /tmp
for dir in "$api" "$scraper" "$lab"; do
  [ -d "$dir/.git" ] || git -C "$dir" init --quiet
done

echo
echo "demo root ready: $DEMO_HOME"
pyenv versions
