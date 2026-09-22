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
core/         event_bus.gd, game_manager.gd             (autoloads)
characters/   character.gd, movement_component.gd, stats_component.gd
player/       player.gd, player.tscn, player_controller.gd, player_interaction.gd
camera/       isometric_camera.gd, occlusion_manager.gd
interaction/  interactable.gd, wall_fixture.gd, door.gd, window.gd (R2)
buildings/    building.gd, room.gd, building_plan.gd, house_blockout.gd (R2)
world/        blockout_box.gd                            (Phase-1 placeholder prop)
ui/hud/       hud.gd, hud.tscn
maps/         test_ground.tscn                           (main scene)
data/         characters/*.tres, buildings/house_a.tres  (content as Resources)
assets/       materials/grid_ground.gdshader
tests/        test_runner.gd, test_case.gd, unit/, integration/, screenshot_run.gd
scripts/      test.sh, screenshots.sh
docs/
```

Planned folders follow the brief (`zombies/`, `ai/`, `inventory/`, `items/`,
`combat/`, `survival/`, `injuries/`, `crafting/`, `simulation/`,
`vehicles/`, `farming/`, `weather/`, `electricity/`, `audio/`, `npc/`).

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
- Pivot → Arm (pitched −30°) → Camera3D. **Orthographic by default**
  (`orthographic = true`): PZ-style 2:1 dimetric look. `zoom_levels`
  are then vertical view sizes (10/14/20/28 world units, default 14); the
  camera sits `orthographic_distance` (45 m) back along the arm so
  near/far and shadows cover the scene. With `orthographic = false` the
  Round-1 perspective rig is used with `perspective_zoom_levels`
  (12/18/26/38 m).
- Yaw snaps in 45° steps (8 headings), smoothly interpolated.
- `view_direction_flat()` (scene → eye, on the ground plane) and
  `eye_position_for(point)` abstract "where is the eye" for both
  projections; the occlusion system uses them instead of the camera
  position (meaningless in ortho).
- In group `isometric_camera`.

### `Interactable` (interaction/interactable.gd, Node3D component)
- Attached as a child of any physics body on layer 4. The body (the
  `provider`) implements `interaction_actions(actor) -> Array[Dictionary]`
  and `interaction_perform(action_id, actor) -> Dictionary` (optional
  `interaction_display_name()`, `interaction_prompt_position()`).
- Action = `{id: StringName, label: String, enabled: bool, reason: String}`.
- `Interactable.of(node)` resolves the component for a body found by
  physics. `perform()` refuses disabled actions (returning their reason)
  and emits `EventBus.interaction_performed`.
- The player never switches on object types: it only talks to this API.

### `PlayerInteraction` (player/player_interaction.gd, child of Player)
- Every physics tick: sphere query (1.6 m, layer 4) → candidates scored by
  distance and facing (things behind the player are ignored beyond 1 m) →
  line-of-sight ray from the eye (`CharacterStatsProfile.eye_height`) to
  the candidate's prompt position on layer 1 (a window behind a wall is not
  targetable) → `current_target`, `current_actions`. Emits
  `EventBus.interaction_target_changed(actor, target, actions)` only when
  the target or the action list changes (structural compare, no strings).
  No target while the character is busy.
- Input: `interact` (E) performs the first enabled action;
  `action_1..action_4` (keys 1-4) pick alternatives. `scripted` flag lets
  tests call `interact()/perform_index()/perform_action()` directly.

### `WallFixture` → `Door` / `HouseWindow` (interaction/)
- `WallFixture` (StaticBody3D) is the shared base: layers 1+4+6, groups
  `wall`, `occluder` + `door`/`window`, metadata `outward`/`wall_height`,
  a `Visual` child with its origin at floor level (occlusion scales it),
  auto-attached `Interactable`, `_box()` builder, tween helpers, a 0.5 s
  `toggle_cooldown` ("Busy") and `_box_blocked()` shape queries.
- `Door`: body sits at the hinge; the leaf is offset along +X so rotating
  the body swings the door with its collision. Before swinging, the leaf
  box at the *target* angle is tested against layers 2+3 (player,
  zombies): overlap → `{ok: false, reason: "Blocked"}`, state unchanged.
  `locked` flag → "Locked".
- `HouseWindow`: full-height collision always (you climb, never walk).
  States closed/open/smashed. `climb(actor)` asks the actor for its busy
  tween (`begin_busy(&"climb")`) and fills it (0.8 s over the sill); the
  ACTOR owns the tween and releases its own lock, so a window freed
  mid-climb cannot leave the player stuck. Duck-typed (`has_method`).
  Result carries `hazard` (smashed glass; injuries in R4).
- `Character.begin_busy(context) -> Tween` / `end_busy()` / `busy_tween`:
  while busy intent is ignored, `move_and_slide()` is skipped and stats
  tick with the busy context (`stamina_rate_climb = -12/s`).

### `Building` / `Room` / `BuildingPlan` / `HouseBlockout` (buildings/)
- `Room` (Node3D): axis-aligned box (`position` = floor centre, `size`);
  `contains_point(world, extra_margin)`; exported `margin` and
  `floor_tolerance`. Group `room`.
- `Building` (Node3D): owns `rooms`, `room_at(p, extra_margin)`,
  `contains_point(p)`, `get_walls()/get_roofs()` (group lookups filtered by
  ancestry), static `Building.locate(tree, p, current_room, exit_margin)`
  with hysteresis: the current room is kept while within `exit_margin`
  (0.35 m) and another room only takes over once the point is that deep
  inside it. Group `building`.
- `BuildingPlan` (Resource): footprint, wall height/thickness, door
  height, window sill/top heights, colours, `rooms` (name + Rect2) and
  `walls` (from/to, optional `outward` normal for exterior walls,
  `openings` of type door/window with `at`, `width`). `validate()` returns
  a list of problems (openings wider than / past the wall, overlaps, zero
  rooms, inconsistent window heights); `HouseBlockout` warns on each.
- `HouseBlockout extends Building`: at `_ready` generates floor slab, wall
  segments split around openings (`segments_for_wall()` is pure and
  unit-tested), lintels above doors, `Door`/`HouseWindow` nodes, `Room`
  volumes and a flat roof (StaticBody3D on layer 6 only, group `roof`).
  Wall segments: StaticBody3D layers 1+6, group `wall`, `Visual` child,
  meta `outward` / `wall_height` / `exterior`.

### `OcclusionManager` (camera/occlusion_manager.gd, node in the map)
- 10 Hz in physics time. Locates the player via `Building.locate`.
- Inside: roofs of that building → `hidden`; exterior wall segments (incl.
  doors/windows) whose `outward · view_direction > 0.3` → `stub` (Visual
  scaled to 0.35 m, collision untouched); interior walls bounding the
  current room that face the eye and lie on its side → `stub`.
- Always: ray(s) from the eye to the player on layer 6 (`occluder`
  group) → `faded` for anything hit that is not already handled. Fading
  uses a per-instance `material_override` (duplicate of the mesh's
  material, alpha 0.15) — shared materials are never mutated;
  `MeshInstance3D.transparency` is a no-op in the Compatibility renderer.
- State per node is remembered; only changes start a 0.2 s tween, so
  standing still never thrashes. Wall/roof lists are cached per building
  (invalidated on exit / `tree_exiting`, freed nodes pruned) and the ray
  query object is reused. Emits `player_room_changed(room, building)`;
  room hysteresis via `Building.locate`.

### `EventBus` signals (so far)
`movement_mode_changed`, `stat_changed`, `stat_threshold`, `sprint_denied`,
`camera_rotated`, `camera_zoomed`, `debug_message`,
`interaction_target_changed(actor, target, actions)`,
`interaction_performed(actor, target, action_id)`,
`interaction_refused(actor, target, reason)`,
`door_state_changed(door, state)`, `window_state_changed(window, state)`,
`window_climbed(actor, window, hazard)`, `player_room_changed(room, building)`.

## Physics layers
1 world · 2 player · 3 zombies · 4 interactables · 5 items · 6 occluders

Walls, doors, windows: 1+6 (+4 for doors/windows). Roofs: 6 only (never
block movement). Props (`BlockoutBox`): 1+6. Player mask: 1+3+4.

## Groups
`player`, `isometric_camera`, `occlusion_manager`, `building`, `room`,
`wall`, `roof`, `floor`, `door`, `window`, `occluder`, `interactable`.

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
