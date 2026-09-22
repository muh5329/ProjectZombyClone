#!/usr/bin/env bash
# Play the game under a virtual display with real input and save screenshots
# to tests/output/. Requires xvfb-run (Linux). On macOS run without xvfb.
set -u
GODOT="${GODOT:-godot}"
command -v "$GODOT" >/dev/null 2>&1 || GODOT="/home/claude/tools/godot"
cd "$(dirname "$0")/.."
RUN="$GODOT --path . --rendering-driver opengl3 -s tests/screenshot_run.gd"
if command -v xvfb-run >/dev/null 2>&1; then
  xvfb-run -a -s "-screen 0 1280x720x24" $RUN 2>&1
else
  $RUN 2>&1
fi | grep -v -E "^ALSA|audio_driver_alsa|All audio drivers failed|audio_server.cpp"
exit "${PIPESTATUS[0]}"
