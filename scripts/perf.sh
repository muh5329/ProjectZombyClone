#!/usr/bin/env bash
# Headless zombie AI performance probe: 200 zombies, 600 physics frames,
# calm (investigating a noise), hostile (all chasing) and noisy (Round 8:
# 30 random sound events / s through SoundManager) and horde-noise (60
# clustered zombies + 10 window smashes / s). Every mode checks avg and p99
# frame time. Pass --noisy or --horde-noise to run only that mode.
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
if [ "$CALM" -ne 0 ] || [ "$HOSTILE" -ne 0 ] || [ "$NOISY" -ne 0 ] || [ "$HORDE" -ne 0 ]; then
  echo "perf.sh: OVER BUDGET (calm $CALM, hostile $HOSTILE, noisy $NOISY, horde-noise $HORDE)"
  exit 1
fi
echo "perf.sh: OK"
exit 0
