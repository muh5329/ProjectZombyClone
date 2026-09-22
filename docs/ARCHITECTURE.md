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
characters/   character.gd, movement_component.gd, stats_component.gd,
              health_component.gd, footstep_emitter.gd, body_helpers.gd (R3)
player/       player.gd, player.tscn, player_controller.gd, player_interaction.gd
camera/       isometric_camera.gd, occlusion_manager.gd
interaction/  interactable.gd, wall_fixture.gd, door.gd, window.gd (R2)
buildings/    building.gd, room.gd, building_plan.gd, house_blockout.gd (R2)
ai/           state_machine/state_machine.gd, state.gd  (generic FSM, R3)
zombies/      zombie.gd/.tscn, zombie_visual.gd, zombie_corpse.gd, zombie_senses.gd,
              zombie_ai.gd, zombie_spawner.gd, states/zombie_state_*.gd (R3)
world/        blockout_box.gd, nav_baker.gd, world_query.gd (R3)
ui/hud/       hud.gd, hud.tscn, damage_vignette.gdshader
maps/         test_ground.tscn                           (main scene)
data/         characters/*.tres, buildings/house_a.tres, zombies/zombie_basic.tres
assets/       materials/grid_ground.gdshader
tests/        test_runner.gd, test_case.gd, unit/, integration/, perf/, screenshot_run.gd
scripts/      test.sh, screenshots.sh, perf.sh
docs/
```

Planned folders follow the brief (`inventory/`, `items/`,
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

### `StateMachine` / `AIState` (ai/state_machine/, RefCounted)
- Generic explicit FSM: `add_state(state)`, `change_to(id)` (exit/enter,
  `state_changed(from, to)`, `previous_state`, bounded `history`),
  `update(delta)` ticks the current state, which returns the id of the
  next state or `&""`. Transient states resolve within the same update
  (chained transitions capped at 4). States hold the machine weakly.
  Pure: no scene tree, delta comes from the caller. NPCs reuse it later.

### `Zombie` (zombies/zombie.gd, CharacterBody3D — deliberately not a Character)
- Physics, damage and component wiring only. Children: `Movement`
  (MovementComponent: walk = shamble, jog = chase — its
  `compute_velocity()` is the one movement model), `Stats` (health),
  `Senses` (ZombieSenses), `AI` (ZombieAI), `Visual` (ZombieVisual),
  `NavigationAgent3D`, `Collision`.
- Children are ready before the parent's `@onready` vars exist, so the
  zombie calls `senses.setup(self)` / `ai.setup(self)` itself.
- `set_intent(direction, mode)`, `face_toward(p)`, `take_damage(amount,
  source, info)` ({ok:false} for ≤ 0; head ×3; stun ≥ stagger_damage;
  otherwise the AI turns toward the source), `die(killer)` → ZombieCorpse.
- One `_physics_process` runs senses, the AI and the movement step (all
  rates from the profile, phases from `ai_seed`); the step is skipped
  while settled; `cheap_movement` (calm, and known to be > cheap_distance
  from the player) integrates the velocity directly and takes the body
  out of the physics space; `hostile` raises the AI rate.

### `ZombieVisual` (zombies/zombie_visual.gd, MeshInstance3D)
- Shared 3-surface mesh and head materials from a `ZombieAssets` node
  under the scene root (never statics: resources held by scripts at exit
  are reported as leaks). Facing lerp, state tint, attack lunge offset,
  swing flash, death collapse. Updated only while `needs_update()`.

### `ZombieCorpse` (zombies/zombie_corpse.gd, StaticBody3D)
- Layer 4 / mask 0, group `corpse`, adopts the zombie's Visual and
  provides the disabled "Search corpse" action. `take_damage` refuses.

### `ZombieSenses` / `ZombieAI` / `ZombieSpawner` / `NavBaker` / `WorldQuery`
- See SYSTEMS.md (Zombies, Navigation). `ZombieSenses.can_see()` is a
  pure static; `ZombieAI` owns the navigation helpers
  (`set_destination`, `move_along_path`, `breakable_ahead` ray on layer
  7, `random_point_near`), the attack-slot registry, `has_attack_line()`
  and a seeded RNG. It imports no Door / Building types: obstacles are
  **breakables** (group `breakable`, duck-typed `take_damage(amount,
  source)` + `blocks_path()`), world lookups go through the static
  `WorldQuery` (`is_inside_building`, `random_nav_point`).
- `BodyHelpers` (characters/body_helpers.gd): flat distance / speed /
  yaw helpers shared by Character and Zombie.
- `NavBaker extends NavigationRegion3D`: bakes on a thread from the map
  root's static colliders (layer 1), then waits for the NavigationServer
  map iteration to advance before `navigation_ready` — queries before
  that return nothing.

### `HealthComponent` (characters/health_component.gd)
- `max_health`, `take_damage(amount, source, info) -> {ok, health, dead}`,
  `heal`, `revive`, `invulnerable`; local `damaged`/`died`/`changed` and
  EventBus `character_damaged` / `character_died` with the owning
  character. `Character` picks up an optional `Health` child, delegates
  `take_damage`, and on death sets `is_busy` (input ignored).

### `FootstepEmitter` (characters/footstep_emitter.gd)
- Child of a Character; emits `sound_emitted` once per second while it
  moves, radius by effective mode (2 / 4 / 8 / 14 m).

### `EventBus` signals (so far)
`movement_mode_changed`, `stat_changed`, `stat_threshold`, `sprint_denied`,
`camera_rotated`, `camera_zoomed`, `debug_message`,
`interaction_target_changed(actor, target, actions)`,
`interaction_performed(actor, target, action_id)`,
`interaction_refused(actor, target, reason)`,
`door_state_changed(door, state)` (open / closed / broken), `door_banged(door, source)`,
`window_state_changed(window, state)`,
`window_climbed(actor, window, hazard)`, `player_room_changed(room, building)`,
`character_damaged(character, amount, source, info)`,
`character_died(character, source)`,
`sound_emitted(position, radius, intensity, category, source)`,
`zombie_state_changed(zombie, from, to)`, `zombie_spotted_target(zombie, target)`,
`zombie_lost_target(zombie)`, `zombie_attacked(zombie, target, hit)`,
`zombie_died(zombie, killer)`.

## Physics layers
1 world · 2 player · 3 zombies · 4 interactables · 5 items · 6 occluders ·
7 doors · 8 window_panes

Walls: 1+6. Windows: sill + header body 1+4+6, glass child body 8 while
closed (0 once open / smashed). Door leaves: 7+4+6 — never on 1, so the
navmesh (baked from layer 1) passes through doorways; broken doors: 4
only. Roofs: 6 only (never block movement). Props (`BlockoutBox`): 1+6.
Player mask: 1+3+7+8 (not 4: corpses on layer 4 are walked over). Zombie
mask: 1+2+3+7+8. Zombie corpses: layer 4, mask 0. Vision / attack /
interaction rays: 1+7+8. Physics engine: Jolt (`physics/3d/physics_engine`).

## Groups
`player`, `isometric_camera`, `occlusion_manager`, `building`, `room`,
`wall`, `roof`, `floor`, `door`, `window`, `occluder`, `interactable`,
`breakable` (doors: `take_damage` + `blocks_path`), `zombie`, `corpse`,
`navigation_mesh_source_group` (the map root; parsed by NavBaker).

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
  `EventBus` (nor call `EventBus` directly — use `root.get_node("EventBus")`).
- Gotcha: `wait_until` counts *process* frames, which run far faster than
  physics headless. Gameplay timers (AI, cooldowns, memory) are waited on
  with `wait_physics_until`.
- `tests/perf/perf_zombies.gd` (`scripts/perf.sh`, calm and `--hostile`)
  measures the scene-tree part of every physics step with two probe
  nodes at the lowest / highest physics priority (all `_physics_process`
  callbacks incl. move_and_slide; the Jolt step for kinematic bodies is
  negligible). `Performance.TIME_PHYSICS_PROCESS` is unusable for this:
  it refreshes once per second and covers whole catch-up bursts.
- `scripts/test.sh` fails on any `SCRIPT ERROR` and on any plain
  `ERROR:` line except the audio-device and `ERR_CANT_OPEN` ones.
- Integration tests of other systems disable the map's zombie spawner
  (`scene.get_node("Zombies").auto_spawn = false`) in `setup()`.
