#!/usr/bin/env bash
# Headless zombie AI performance probe: 200 zombies, 600 physics frames,
# once calm (investigating a noise) and once hostile (all chasing).
# Prints avg physics ms; exits 1 when over budget (see tests/perf/perf_zombies.gd).
set -u
GODOT="${GODOT:-godot}"
command -v "$GODOT" >/dev/null 2>&1 || GODOT="/home/claude/tools/godot"
cd "$(dirname "$0")/.."
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
FILTER='^ALSA|audio_driver_alsa|All audio drivers failed|audio_server.cpp'
echo "== calm/loud (200 zombies investigating a noise; budget 8 ms)"
"$GODOT" --headless --path . -s tests/perf/perf_zombies.gd 2>&1 | grep -v -E "$FILTER"
CALM=${PIPESTATUS[0]}
echo "== hostile (200 zombies chasing the player; budget 10 ms)"
"$GODOT" --headless --path . -s tests/perf/perf_zombies.gd -- --hostile 2>&1 | grep -v -E "$FILTER"
HOSTILE=${PIPESTATUS[0]}
if [ "$CALM" -ne 0 ] || [ "$HOSTILE" -ne 0 ]; then
  echo "perf.sh: OVER BUDGET (calm exit $CALM, hostile exit $HOSTILE)"
  exit 1
fi
echo "perf.sh: OK"
exit 0
