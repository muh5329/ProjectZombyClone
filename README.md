# Project Zomb

Isometric 3D survival sandbox in Godot 4.6 (GDScript), inspired by the
systemic gameplay of Project Zomboid. Blockout phase.

## Run
Open `project.godot` in Godot 4.6 and press Play (main scene:
`maps/test_ground.tscn`).

Controls: WASD move · Shift sprint · Ctrl sneak · Alt walk · Q/R rotate
camera · mouse wheel / +/- zoom · F3 debug overlay.

## Test
```
GODOT=/path/to/godot scripts/test.sh                 # all
GODOT=/path/to/godot scripts/test.sh unit            # unit only
GODOT=/path/to/godot scripts/test.sh --filter=camera # by name
GODOT=/path/to/godot scripts/screenshots.sh          # gameplay run + PNGs
GODOT=/path/to/godot scripts/perf.sh                 # 200-zombie AI perf probe
```
On macOS: `GODOT="/Applications/Godot.app/Contents/MacOS/Godot"`.

## Docs
`docs/MASTER_PLAN.md` · `docs/PROGRESS.md` · `docs/ARCHITECTURE.md` ·
`docs/SYSTEMS.md` · `docs/KNOWN_ISSUES.md` · `docs/BRIEF.md` (original brief)
