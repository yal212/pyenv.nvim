#!/usr/bin/env bash
#
# Turn the real install recording into a watchable GIF.
#
# The build genuinely takes minutes, and how many is not reproducible, so the
# boundaries are measured from the *ends* rather than from absolute timestamps:
# the first HEAD seconds and last TAIL seconds play untouched, and whatever is
# between them -- pure compilation scroll -- is squeezed to MIDDLE seconds
# whether the build ran for four minutes or twelve.
set -euo pipefail

SRC="${1:-demo/out/install.mp4}"
DEST="${2:-assets/install.gif}"

HEAD=6      # typing the command, the window opening, the first real output
TAIL=10     # the completion notice, and setting the new version as global
MIDDLE=5    # what the compile scroll is compressed to
FPS=20

[ -f "$SRC" ] || { echo "compress.sh: no recording at $SRC (run: vhs demo/install.tape)" >&2; exit 1; }

duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$SRC")
duration=${duration%.*}

palette="fps=${FPS},split[s0][s1];[s0]palettegen=stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle"

if [ "$duration" -le $((HEAD + TAIL + MIDDLE)) ]; then
  # Too short to be worth cutting up -- something went wrong with the build, but
  # produce a usable GIF rather than a broken one.
  echo "compress.sh: recording is only ${duration}s; converting without compression"
  ffmpeg -y -v error -i "$SRC" -vf "$palette" -loop 0 "$DEST"
else
  cut=$((duration - TAIL))
  speed=$(( (cut - HEAD) / MIDDLE ))
  echo "compress.sh: ${duration}s recording -> ${HEAD}s + ${MIDDLE}s (${speed}x) + ${TAIL}s"
  ffmpeg -y -v error -i "$SRC" -filter_complex "\
[0:v]trim=start=0:end=${HEAD},setpts=PTS-STARTPTS[a];\
[0:v]trim=start=${HEAD}:end=${cut},setpts=(PTS-STARTPTS)/${speed}[b];\
[0:v]trim=start=${cut},setpts=PTS-STARTPTS[c];\
[a][b][c]concat=n=3:v=1:a=0,${palette}" -loop 0 "$DEST"
fi

echo "compress.sh: wrote $DEST ($(du -h "$DEST" | cut -f1))"
