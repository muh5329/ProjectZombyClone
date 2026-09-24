#!/usr/bin/env bash
# Headless zombie AI performance probe: 200 zombies, 600 physics frames,
# calm (investigating a noise), hostile (all chasing) and noisy (Round 8:
# 30 random sound events / s through SoundManager) and horde-noise (60
# clustered zombies + 10 window smashes / s). Every mode checks avg and p99
# frame time. Pass --noisy or --horde-noise to run only that mode; --save runs
# only the Round-10 save / load timing (tests/perf/perf_save.gd); --world runs
# only the Round-11 generated-world probe (tests/perf/perf_world.gd) and the
# Round-12 streaming probe (tests/perf/perf_streaming.gd).
# Prints avg physics ms; exits 1 when over budget (see tests/perf/perf_zombies.gd).
set -u
GODOT="${GODOT:-godot}"
command -v "$GODOT" >/dev/null 2>&1 || GODOT="/home/claude/tools/godot"
cd "$(dirname "$0")/.."
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
FILTER='^ALSA|audio_driver_alsa|All audio drivers failed|audio_server.cpp'
run_noisy() {
  echo "== noisy (200 zombies + 30 sound events/s at random positions; budget 10 ms)"
  "$GODOT" --headless --path . -s tests/perf/perf_zombies.gd -- --noisy 2>&1 | grep -v -E "$FILTER"
  return ${PIPESTATUS[0]}
}
run_horde() {
  echo "== horde-noise (60 clustered zombies + 10 window smashes/s next to them; avg 10 ms, p99 20 ms)"
  "$GODOT" --headless --path . -s tests/perf/perf_zombies.gd -- --horde-noise 2>&1 | grep -v -E "$FILTER"
  return ${PIPESTATUS[0]}
}
run_world() {
  echo "== world (Round 11: generated county seed 1337, player on the main street + 40 zombies; layout < 2 s, load < 8 s, avg 10 ms, p99 16 ms)"
  "$GODOT" --headless --path . -s tests/perf/perf_world.gd 2>&1 | grep -v -E "$FILTER"
  local W=${PIPESTATUS[0]}
  echo "== streaming (Round 12: memory over 2 x 1 km, sprint town / woods frames, population tick with 1000 zombies < 1 ms, save / load with 50 changes)"
  "$GODOT" --headless --path . -s tests/perf/perf_streaming.gd 2>&1 | grep -v -E "$FILTER"
  local S=${PIPESTATUS[0]}
  if [ "$W" -ne 0 ] || [ "$S" -ne 0 ]; then return 1; fi
  return 0
}
if [ "${1:-}" = "--world" ]; then
  run_world
  R=$?
  if [ "$R" -ne 0 ]; then echo "perf.sh: OVER BUDGET (world)"; exit 1; fi
  echo "perf.sh: OK"
  exit 0
fi
if [ "${1:-}" = "--save" ]; then
  echo "== save / load (200 living zombies + 20 corpses; save < 200 ms, load < 3 s)"
  "$GODOT" --headless --path . -s tests/perf/perf_save.gd 2>&1 | grep -v -E "$FILTER"
  R=${PIPESTATUS[0]}
  if [ "$R" -ne 0 ]; then echo "perf.sh: OVER BUDGET (save/load)"; exit 1; fi
  echo "perf.sh: OK"
  exit 0
fi
if [ "${1:-}" = "--noisy" ] || [ "${1:-}" = "--horde-noise" ]; then
  if [ "$1" = "--noisy" ]; then run_noisy; else run_horde; fi
  R=$?
  if [ "$R" -ne 0 ]; then echo "perf.sh: OVER BUDGET ($1 exit $R)"; exit 1; fi
  echo "perf.sh: OK"
  exit 0
fi
echo "== calm/loud (200 zombies investigating a noise; budget 8 ms)"
"$GODOT" --headless --path . -s tests/perf/perf_zombies.gd 2>&1 | grep -v -E "$FILTER"
CALM=${PIPESTATUS[0]}
echo "== hostile (200 zombies chasing the player; budget 10 ms)"
"$GODOT" --headless --path . -s tests/perf/perf_zombies.gd -- --hostile 2>&1 | grep -v -E "$FILTER"
HOSTILE=${PIPESTATUS[0]}
run_noisy
NOISY=$?
run_horde
HORDE=$?
echo "== save / load (Round 10: 200 living zombies + 20 corpses: save < 200 ms, load < 3 s; 3000 dropped items: save < 200 ms, load < 2 s)"
"$GODOT" --headless --path . -s tests/perf/perf_save.gd 2>&1 | grep -v -E "$FILTER"
SAVE=${PIPESTATUS[0]}
run_world
WORLD=$?
if [ "$CALM" -ne 0 ] || [ "$HOSTILE" -ne 0 ] || [ "$NOISY" -ne 0 ] || [ "$HORDE" -ne 0 ] || [ "$SAVE" -ne 0 ] || [ "$WORLD" -ne 0 ]; then
  echo "perf.sh: OVER BUDGET (calm $CALM, hostile $HOSTILE, noisy $NOISY, horde-noise $HORDE, save/load $SAVE, world $WORLD)"
  exit 1
fi
echo "perf.sh: OK"
exit 0
