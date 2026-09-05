# `:Pyenv install` streaming into the floating window, against a root where
# 3.13.2 genuinely is not installed yet.
#
#   make demo            (from the repo root)
#
# This films a real CPython build, so it runs for minutes. The output is an mp4
# that demo/compress.sh time-compresses into assets/install.gif.

Output demo/out/install.mp4

Require nvim
Require pyenv

# Identical to tour.tape, so the two GIFs read as one set.
Set Shell "bash"
Set FontFamily "JetBrainsMono Nerd Font Mono"
Set FontSize 17
Set Width 1200
Set Height 700
Set Padding 20
Set Framerate 20
Set TypingSpeed 60ms

# A real build's length is not knowable in advance, so the tape waits on the
# plugin's own completion notice (command.lua) instead of guessing a Sleep.
Set WaitTimeout 1800s

Hide
Type "REPO=$PWD" Enter
Type "export PYENV_ROOT=/tmp/pyenv-demo/.pyenv-install" Enter
Type "rm -rf /tmp/pyenv-demo/.pyenv-install && mkdir -p /tmp/pyenv-demo/.pyenv-install/versions" Enter
Type "cd /tmp/pyenv-demo/code/lab && clear" Enter
Type "nvim --clean -u $REPO/demo/init.lua main.py" Enter
Sleep 3s
Show

Sleep 2s
Type ":Pyenv install 3.13.2" Sleep 700ms Enter
Sleep 7s

# The window never takes focus, so this lands in the buffer underneath it.
Type "o# ...and you can keep working while it builds" Sleep 1s
Escape
Sleep 3s

Wait+Screen /pyenv\.nvim: installed 3\.13\.2/
Sleep 3s

# The version is real and immediately usable.
Type ":Pyenv global 3.13.2" Sleep 700ms Enter
Sleep 5s
