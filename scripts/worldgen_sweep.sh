#!/usr/bin/env bash
# Round 11 perf lane (report only, not part of test.sh): generate and fully
# validate many world layouts — overlaps (rotated boxes), road crossings /
# overlaps / water, props vs driveways / doors, fences vs vehicles,
# connectivity, doors, content — and print every problem.
# Usage: scripts/worldgen_sweep.sh [first_seed=1] [count=200] [--size=768] [--plans]
# Exit 0 only when there are 0 problems.
set -u
GODOT="${GODOT:-godot}"
command -v "$GODOT" >/dev/null 2>&1 || GODOT="/home/claude/tools/godot"
cd "$(dirname "$0")/.."
FIRST="${1:-1}"
COUNT="${2:-200}"
shift $(( $# > 2 ? 2 : $# ))
"$GODOT" --headless --path . -s tests/tools/world_validate.gd -- "$FIRST" "$COUNT" --quiet "$@" 2>&1 \
  | grep -v -E "^ALSA|audio_driver_alsa|All audio drivers failed|audio_server.cpp|^Godot Engine|^$"
exit "${PIPESTATUS[0]}"
