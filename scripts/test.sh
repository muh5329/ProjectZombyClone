#!/usr/bin/env bash
# Run the headless test suite. Usage: scripts/test.sh [unit|integration] [--filter=name]
set -u
GODOT="${GODOT:-godot}"
command -v "$GODOT" >/dev/null 2>&1 || GODOT="/home/claude/tools/godot"
cd "$(dirname "$0")/.."
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
OUT="$("$GODOT" --headless --path . -s tests/test_runner.gd -- "$@" 2>&1)"
CODE=$?
echo "$OUT" | grep -v -E "^ALSA|audio_driver_alsa|All audio drivers failed|audio_server.cpp"
if echo "$OUT" | grep -q "SCRIPT ERROR"; then
  echo "test.sh: SCRIPT ERROR detected in engine output -> FAIL"
  exit 1
fi
exit $CODE
