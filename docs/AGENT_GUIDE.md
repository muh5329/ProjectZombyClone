# Agent Guide (read before touching the project)

Project: `/home/claude/zomb` — Godot 4.6, GDScript, isometric 3D survival
sandbox inspired by Project Zomboid. Godot binary: `/home/claude/tools/godot`.

## Commands
- `scripts/test.sh` — full headless suite (unit + integration). Must exit 0.
  Fails on any `SCRIPT ERROR` in engine output. `scripts/test.sh --filter=x`.
- `scripts/screenshots.sh` — plays the game with real input under Xvfb and
  writes PNGs to `tests/output/`. Must print `SCREENSHOT_RUN: OK`.
- After adding a new `class_name`, the class cache must refresh:
  `test.sh` runs `--import` for you. If you run godot directly, run
  `godot --headless --path . --import` first.

## Conventions
- Components over inheritance. Logic in small Nodes/RefCounted classes that
  can be unit-tested; scene nodes only integrate.
- Cross-system communication through `EventBus` (autoload) signals with
  plain payloads (Node refs, StringName ids, Dictionaries).
- Content is data: `Resource` subclasses under `data/` + `.tres` files.
  Never hardcode item/recipe/loot definitions in logic.
- Objects provide their own interactions (`Interactable.get_actions()`);
  never switch on object type inside the player.
- Every gameplay feature gets: a unit test if it has pure logic, an
  integration test in `tests/integration/` that runs the real scene, and
  (if visible) a step in `tests/screenshot_run.gd`.
- Hand-written `.tscn`: all `[ext_resource]` before `[sub_resource]`;
  use `position`/`rotation_degrees`, not hand-typed `Transform3D`.
- `-s` SceneTree scripts (runners) must not statically type against
  gameplay classes (they compile before autoloads exist).
- Lambdas capture locals by value: use an Array/Dictionary holder.
- Tests that wait on interpolation use `wait_until(pred, max_frames)`.
- Physics-time, not wall-clock, for gameplay timers.

## Visual target (Project Zomboid references in docs/reference/)
- Fixed dimetric camera: orthographic, ~30° elevation, 45° yaw steps.
- Indoors: walls facing the camera are cut away / faded, roof hidden, the
  room interior fully readable (reference 4). Outdoors: roofs visible.
- Dense readable blocks: roads with lane markings, sidewalks, fences,
  parked cars, props, trees; zombies as dozens of small figures (ref 1-2).
- Night: dark blue ambient with warm point lights from windows / street
  lamps (reference 3).
- Blockout first: primitives with flat colours, but composition and
  readability must already match the references.

## Definition of done for a round
1. `scripts/test.sh` passes; `scripts/screenshots.sh` OK.
2. Feature works in real gameplay through the input map.
3. Independent critic ran, findings fixed, re-tested from clean.
4. `docs/PROGRESS.md` entry (goal, changes, files, systems, tests,
   evidence, bugs found/fixed, failed approaches, verifier score, top
   remaining issue, next action). `SYSTEMS.md`, `ARCHITECTURE.md`,
   `KNOWN_ISSUES.md`, `MASTER_PLAN.md` updated.
5. Commit.
