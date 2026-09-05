# The hero GIF: which interpreter is active, and why it won.
#
#   make demo            (from the repo root -- Output paths are relative to it)
#
# Run demo/setup.sh first; this films a real $PYENV_ROOT, not a fixture.

Output assets/demo.gif

Require nvim
Require pyenv

Set Shell "bash"
Set FontFamily "JetBrainsMono Nerd Font Mono"
Set FontSize 17
# Wide enough that the resolved interpreter path prints on one line. Wrapping it
# costs an extra row, which pushes `:Pyenv status` past cmdheight and turns the
# whole beat into a hit-enter prompt.
Set Width 1200
Set Height 700
Set Padding 20
Set Framerate 20
Set TypingSpeed 60ms
Set WaitTimeout 30s

# Shell scaffolding is not the demo: open on the editor, already resolved.
Hide
Type "REPO=$PWD" Enter
Type "export PYENV_ROOT=/tmp/pyenv-demo/.pyenv" Enter
Type "cd /tmp/pyenv-demo/code/api && clear" Enter
Type "nvim --clean -u $REPO/demo/init.lua app.py" Enter
Sleep 3s
Show

Sleep 2s

# 1. Why this interpreter? The answer names the file that decided it.
Type ":Pyenv" Sleep 700ms Enter
Sleep 4500ms
# Ctrl+L clears the message area, so each beat starts on a clean screen instead
# of scrolling the buffer away under a pile of old output.
Ctrl+L
Sleep 700ms

# 2. Switch. The picker is vim.ui.select, so it adopts whatever you already use;
#    with no picker installed this is Neovim's own prompt.
Type ":Pyenv select" Sleep 500ms Enter
Sleep 2500ms
Type "2" Sleep 800ms Enter
Sleep 2500ms
Enter
Sleep 2s
Ctrl+L
Sleep 700ms

# 3. The pin is per-project and lives outside the repository; reset drops it.
Type ":Pyenv reset" Sleep 500ms Enter
Sleep 3s
Ctrl+L
Sleep 700ms

# 4. Change directory, and it re-resolves on its own -- by a different rule.
Type ":cd ../scraper" Sleep 500ms Enter
Sleep 1500ms
Type ":e scrape.py" Enter
Sleep 2s
Type ":Pyenv" Sleep 700ms Enter
Sleep 5s
