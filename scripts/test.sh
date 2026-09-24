#!/usr/bin/env bash
# Run the headless test suite.
# Usage: scripts/test.sh [unit|integration|integration-a..e] [--filter=name] [--shard=K/N]
#   integration-a … -e = the five balanced fifths of the integration suite
#   (--shard=1/5 … 5/5; five since Round 12's streaming tests); each stays
#   well under a 10-minute per-call cap (the whole integration run is
#   ~28 min since the Round-10 unstaged acceptance playthroughs).
set -u
GODOT="${GODOT:-godot}"
command -v "$GODOT" >/dev/null 2>&1 || GODOT="/home/claude/tools/godot"
cd "$(dirname "$0")/.."
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
ARGS=()
for a in "$@"; do
  case "$a" in
    integration-a) ARGS+=(integration --shard=1/5) ;;
    integration-b) ARGS+=(integration --shard=2/5) ;;
    integration-c) ARGS+=(integration --shard=3/5) ;;
    integration-d) ARGS+=(integration --shard=4/5) ;;
    integration-e) ARGS+=(integration --shard=5/5) ;;
    *) ARGS+=("$a") ;;
  esac
done
OUT="$("$GODOT" --headless --path . -s tests/test_runner.gd -- "${ARGS[@]}" 2>&1)"
CODE=$?
echo "$OUT" | grep -v -E "^ALSA|audio_driver_alsa|All audio drivers failed|audio_server.cpp"
if echo "$OUT" | grep -q "SCRIPT ERROR"; then
  echo "test.sh: SCRIPT ERROR detected in engine output -> FAIL"
  exit 1
fi
# Plain engine errors fail too (leaked resources, bad calls…), except the
# known harmless ones: no audio device, and the fontconfig/XDG open failure.
BAD="$(echo "$OUT" | grep -E "^ERROR:" | grep -v -E "ALSA|audio|ERR_CANT_OPEN" || true)"
if [ -n "$BAD" ]; then
  echo "test.sh: ERROR lines in engine output -> FAIL"
  echo "$BAD"
  exit 1
fi
exit $CODE
