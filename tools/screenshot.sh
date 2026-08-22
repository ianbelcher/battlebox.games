#!/usr/bin/env bash
#
# LOOK AT THE GAME WITHOUT A SCREEN.
#
#     tools/screenshot.sh [out-dir] [seconds]
#
# Runs the real client under a virtual X server and saves a PNG every 1.5
# seconds. Use it for anything visual — a menu, the lobby, a HUD change,
# a block icon — instead of deploying and squinting, or worse, reasoning
# about what a layout will probably do.
#
# It is worth having because the alternative is not "check it later", it
# is "do not check it". A UI bug is invisible to every other check in this
# repository: the unit tests pass, the integration run reaches the world,
# the console is clean, and the screen is unreadable. Three real ones were
# found this way in one afternoon — a first screen whose text boxes were
# twelve pixels tall, a symbol that drew as an empty box, and a Play button
# that silently never took focus.
#
# Pass anything else through the environment, exactly as you would to a
# normal run:
#
#     # the lobby, against a lobby you have running
#     WORLD_SERVER_URL=ws://127.0.0.1:9080/ws tools/screenshot.sh /tmp/shots
#
#     # in the world, with two bots, straight into one room
#     WORLD_SERVER_URL=ws://127.0.0.1:9080/ws WORLD_ROOM=brave-otter \
#       WORLD_AUTOTEST=2 tools/screenshot.sh /tmp/shots 40
#
#     # a battle, no server needed — point at nothing and it sits on the
#     # lobby screen, which is what you want for menu work
#     tools/screenshot.sh /tmp/shots
#
# Then read the PNGs. Skip the first two or three: they catch the window
# mid-build.
#
# Software rendering is slow, and slowest once players have joined, because
# every chunk is meshed on the CPU behind two or four SubViewports. For menu
# work the default 25 seconds is plenty; with WORLD_AUTOTEST set, ask for 60
# or you will get two pictures.

set -euo pipefail

OUT="${1:-/tmp/battlebox-shots}"
SECONDS_TO_RUN="${2:-25}"
RES="${SCREENSHOT_RES:-1280x800}"
GODOT="${GODOT:-godot}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

command -v xvfb-run >/dev/null 2>&1 || {
  echo "xvfb-run not found. apt-get install xvfb" >&2; exit 1; }
command -v "$GODOT" >/dev/null 2>&1 || {
  echo "$GODOT not found. Set GODOT=/path/to/godot" >&2; exit 1; }

rm -rf "$OUT" && mkdir -p "$OUT"

# --rendering-method gl_compatibility, and it is NOT optional here.
#
# The default is Forward+, which on a machine with no GPU falls to
# lavapipe — and lavapipe ABORTS this project on startup, with a C++
# backtrace and no hint that the renderer is the problem. gl_compatibility
# is also what the browser build runs, so what you photograph is what most
# players actually see.
#
# LIBGL_ALWAYS_SOFTWARE makes Mesa stop looking for hardware it will not
# find, which is faster than letting it try and fall back.
#
# WORLD_SERVER_URL is deliberately left alone if the caller set it. With
# nothing set the client cannot reach a server, sits on the lobby screen,
# and that is a perfectly good thing to photograph.
echo "==> rendering ${RES} for ${SECONDS_TO_RUN}s into ${OUT}"
set +e
timeout "${SECONDS_TO_RUN}" xvfb-run -a --server-args="-screen 0 ${RES}x24" \
  env WORLD_SHOTS="$OUT" LIBGL_ALWAYS_SOFTWARE=1 \
  "$GODOT" --path "$HERE/game" \
    --rendering-method gl_compatibility \
    --resolution "$RES" \
  > "$OUT/run.log" 2>&1
set -e

shots="$(find "$OUT" -name 'shot_*.png' | wc -l)"
if [ "$shots" -eq 0 ]; then
  echo "no screenshots — the run failed. Last of ${OUT}/run.log:" >&2
  tail -20 "$OUT/run.log" >&2
  exit 1
fi

# A run that draws pictures can still be broken; say so rather than leaving
# somebody to spot it in a PNG — or, more likely, not spot it.
#
# Anything with a GDScript backtrace under it came from OUR code, which is
# how an engine-level ERROR gets reported. That distinction is what makes
# this worth printing: the log is otherwise full of ALSA failures, because
# there is no sound card, and they are not our problem. `grab_focus` on a
# node that was not in the tree yet surfaced exactly here, as one ERROR in
# a run whose screenshots looked perfectly fine.
ours="$(awk '/SCRIPT ERROR|Parse Error|Compile Error/ { print; next }
             /^ERROR:/ { msg = $0; hunt = 4; next }
             hunt-- > 0 && /GDScript backtrace/ { print msg; hunt = 0 }' \
        "$OUT/run.log" | head -5)"
if [ -n "$ours" ]; then
  echo "WARNING: the run logged errors from this project —" >&2
  printf '%s\n' "$ours" >&2
fi

echo "==> ${shots} screenshots in ${OUT}"
ls "$OUT"/shot_*.png | tail -5
