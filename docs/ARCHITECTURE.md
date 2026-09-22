# Architecture

## Principles

- **Components over inheritance.** A character is a `CharacterBody3D` with
  small logic nodes as children (`Movement`, `Stats`, later `Health`,
  `Inventory`…). Components hold logic and data; the character node only
  integrates them per physics tick.
- **Pure logic where possible.** `MovementComponent.compute_velocity()` and
  `PlayerController.camera_relative()` are pure functions — unit-tested
  without a physics world.
- **Intent, not input.** Characters receive `set_intent(direction, mode)`.
  The player controller produces intent from input; AI will produce it from
  behaviours. The character never reads `Input`.
- **Events over references.** Cross-system notifications go through the
  `EventBus` autoload. Emitters never know their listeners.
- **Autoloads stay thin.** `GameManager` holds only the player reference and
  debug flags. Future managers (`TimeManager`, `SaveManager`,
  `WorldManager`) are separate autoloads with single responsibilities.
- **Data-driven content** (from Round 5 on): items, loot tables, recipes,
  zombies as `Resource` files under `data/`.

## Folder layout (current)

```
core/        event_bus.gd, game_manager.gd             (autoloads)
characters/  character.gd, movement_component.gd, stats_component.gd
player/      player.gd, player.tscn, player_controller.gd
camera/      isometric_camera.gd
world/       blockout_box.gd                            (Phase-1 placeholder prop)
ui/hud/      hud.gd, hud.tscn
maps/        test_ground.tscn                           (main scene)
assets/      materials/grid_ground.gdshader
tests/       test_runner.gd, test_case.gd, unit/, integration/, screenshot_run.gd
scripts/     test.sh, screenshots.sh
docs/
```

Planned folders follow the brief (`zombies/`, `ai/`, `inventory/`, `items/`,
`combat/`, `survival/`, `injuries/`, `interaction/`, `buildings/`,
`crafting/`, `simulation/`, `vehicles/`, `farming/`, `weather/`,
`electricity/`, `audio/`, `npc/`, `data/`).

## Key types

### `Character` (characters/character.gd, extends CharacterBody3D)
- Owns `movement: MovementComponent`, `stats: StatsComponent`, optional
  `Visual` child rotated to face travel direction.
- `set_intent(direction, mode)` — called by controller/AI.
- Each physics tick: updates stamina → resolves the *effective* mode
  (sprint denied when exhausted or standing still) → computes velocity →
  `move_and_slide()` → emits `movement_mode_changed` on change.
- Stamina hysteresis: exhausted at ≤2 %, recovers at ≥25 %. While exhausted
  a `&"exhaustion"` speed modifier (×0.75) is applied.

### `MovementComponent`
- Mode enum SNEAK/WALK/JOG/SPRINT with base speeds 1.3/2.0/3.4/5.6 m/s.
- `speed_modifiers: Dictionary[StringName, float]` — multiplicative, keyed
  by source (`encumbrance`, `injury`, `exhaustion`…). Systems set/clear
  their own key and never touch each other's.
- Acceleration 14 m/s², deceleration 22 m/s² — no instant starts.

### `StatsComponent`
- Named stats with max, value, optional passive regen, and named thresholds
  (`{&"low": 0.25, &"exhausted": 0.02}`) that emit `threshold` once per
  transition, both locally and on the EventBus.
- `to_dict()/from_dict()` for the save system.

### `PlayerController`
- Reads the input map every physics tick and sets intent on the parent.
- `scripted` flag lets tests/cutscenes inject intent without input.
- Movement is camera-relative: `camera_relative(input, camera)` projects the
  active camera's forward/right onto the ground plane.

### `IsometricCamera`
- Pivot → Arm (pitched −52°) → Camera3D (fov 35, perspective).
- Yaw snaps in 45° steps (8 headings), smoothly interpolated.
- Zoom levels 12/18/26/38 m; default 26 m (≈16 m of ground visible).
- Exposes `camera` for the occlusion system (Round 2).

### `EventBus` signals (so far)
`movement_mode_changed`, `stat_changed`, `stat_threshold`,
`camera_rotated`, `camera_zoomed`, `debug_message`.

## Physics layers
1 world · 2 player · 3 zombies · 4 interactables · 5 items · 6 occluders

## Testing

- `tests/test_runner.gd` (SceneTree script) discovers `tests/*/test_*.gd`,
  runs `test_*` coroutines with real physics, writes
  `tests/output/report.txt`, exits non-zero on failure.
- Integration tests instantiate the real main scene and drive the real
  `PlayerController` in scripted mode.
- `tests/screenshot_run.gd` drives the game through **real input actions**
  (`Input.parse_input_event`) so the input map itself is exercised, and saves
  PNG evidence.
- Gotcha: scripts launched with `-s` compile before autoloads exist, so they
  must not statically type against gameplay classes that reference
  `EventBus`.
