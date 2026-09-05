# Recording the README GIFs

Both GIFs in the README are recorded with [VHS][vhs] against a **real** pyenv
installation — real CPython builds, real pyenv-virtualenvs, a real `.venv`.
Nothing here stubs an interpreter, because the whole point of the recordings is
the resolution output, and resolution that is only true of a fixture would be
worth nothing.

```sh
brew install vhs pyenv pyenv-virtualenv   # vhs pulls in ttyd and ffmpeg
make demo                                 # from the repo root
```

The first run builds two CPython versions and takes a while. Everything after
that is cheap: `demo/setup.sh` is idempotent and skips what already exists.

| File | |
|---|---|
| `setup.sh` | Builds the demo world under `/tmp/pyenv-demo` |
| `init.lua` | The Neovim config being recorded — no plugin dependencies |
| `tour.tape` | `assets/demo.gif` — resolution, switching, auto-activation |
| `install.tape` | `demo/out/install.mp4` — a genuine `pyenv install` |
| `compress.sh` | Time-compresses that mp4 into `assets/install.gif` |

## The demo world

`setup.sh` builds everything under `$DEMO_HOME` (`/tmp/pyenv-demo` by default)
rather than your own `~/.pyenv`. That is not tidiness: `:Pyenv status` prints
absolute paths, so recording against a real home directory would bake a personal
path into a public README.

```
/tmp/pyenv-demo
├── .pyenv/                 3.12.4, 3.13.2, api-env, scraper-env
└── code/
    ├── api/                .python-version -> api-env      (resolves by `local`)
    ├── scraper/            .venv from 3.13.2               (resolves by `project_venv`)
    └── lab/                no markers at all               (resolves by `system`)
```

Three projects because three different resolution steps win in them, which is
the argument the tour is making.

## Why the install is filmed separately

`install.tape` points `$PYENV_ROOT` at a **second, disposable** root that it
wipes on every run, so the build it records is always genuinely from nothing.
Filming against the populated root would hit `pyenv install -s` on a version
that already exists, which returns instantly and shows an empty window.

The build takes minutes and how many is not reproducible, so:

- the tape waits on the plugin's own `pyenv.nvim: installed <version>` notice
  (`Wait+Screen`) rather than guessing a `Sleep`;
- `compress.sh` measures the recording's ends rather than absolute timestamps —
  the first 6s and last 10s play untouched, and the compile scroll between them
  is squeezed to about 5s whether the build ran for four minutes or twelve.

That is the only manipulation applied to either recording, and the README says
so next to the image.

## Re-recording after a UI change

Anything that changes what the plugin puts on screen — the wording of
`:Pyenv status`, the picker labels, the progress window — dates these GIFs. Run
`make demo` and commit the result.

Two things to check when you do:

- **Nothing wraps.** The resolved interpreter path is the longest line on
  screen. If it wraps, `:Pyenv status` grows past `cmdheight` and the beat turns
  into a `Press ENTER` prompt. Widen `Set Width` in the tape, or raise
  `cmdheight` in `init.lua`.
- **Keep both GIFs under ~2MB.** The levers, in order: `Set Framerate`
  (20 → 16), then `Set Width`, then cut a beat.

[vhs]: https://github.com/charmbracelet/vhs
