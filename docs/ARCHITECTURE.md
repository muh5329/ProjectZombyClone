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
player/       player.gd, player.tscn, player_controller.gd, player_interaction.gd,
              player_combat_input.gd (R4)
camera/       isometric_camera.gd, occlusion_manager.gd
interaction/  interactable.gd, wall_fixture.gd, door.gd, window.gd (R2), loot_container.gd, container_visual.gd (R5)
buildings/    building.gd, room.gd, building_plan.gd, house_blockout.gd (R2), furniture_catalog.gd (R5)
ai/           state_machine/state_machine.gd, state.gd  (generic FSM, R3)
items/        item_data.gd, weapon_data.gd, item_instance.gd, world_item.gd (R4),
              food_data.gd, medical_data.gd, container_item_data.gd, item_db.gd (autoload ItemDB) (R5)
inventory/    item_container.gd (ItemContainer), container_access.gd (ContainerAccess) (R5),
              equipment.gd (Equipment), hotbar.gd (Hotbar), encumbrance.gd (Encumbrance), item_actions.gd (ItemActions) (R6)
loot/         loot_table.gd, loot_table_db.gd (autoload LootTableDB), loot_resolver.gd (R5)
combat/       melee_combat.gd, swing_state_machine.gd, hit_resolver.gd, melee_visuals.gd (R4)
injuries/     injury.gd, injury_type_spec.gd, injury_component.gd (R4)
effects/      blood_decals.gd (R4)
zombies/      zombie.gd/.tscn, zombie_visual.gd, zombie_corpse.gd, zombie_senses.gd,
              zombie_ai.gd, zombie_spawner.gd, states/zombie_state_*.gd (R3)
world/        blockout_box.gd, nav_baker.gd, world_query.gd (R3), world_config.gd, world_state.gd (R5)
ui/hud/       hud.gd, hud.tscn, damage_vignette.gdshader, hotbar.gd (HotbarWidget, R6)
ui/inventory/ loot_window.gd/.tscn (LootWindow controller), item_list_panel.gd (ItemListPanel),
              item_context_menu.gd (ItemContextMenu), inventory_drag_drop.gd (InventoryDragDrop) (R5/R6)
maps/         test_ground.tscn                           (main scene)
data/         characters/*.tres, buildings/{house_a,shed_a,furniture_catalog}.tres, zombies/zombie_basic.tres,
              items/<category>/*.tres (41 items, R5), loot/*.tres + loot/garage/*.tres (R5),
              combat/combat_profile.gd + .tres, injuries/injury_profile.gd + human_injuries.tres (R4)
assets/       materials/grid_ground.gdshader
tests/        test_runner.gd, test_case.gd, unit/, integration/, perf/, screenshot_run.gd
scripts/      test.sh, screenshots.sh, perf.sh
docs/
```

Planned folders follow the brief (`inventory/`, `survival/`, `crafting/`, `simulation/`,
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
- R6: `sprint_locks {source: reason}` (`set_sprint_lock`,
  `sprint_denied_reason()` — "Too heavy" / "Too winded to sprint");
  `can_sprint()` = not exhausted and no lock.

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
- R6: `set_drain_multiplier(stat, source, mult)` / `drain_multiplier()`
  scale NEGATIVE rates only in `tick()` (encumbrance).

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
  source, info)` ({ok:false} for ≤ 0; head ×3; ×1.5 while knocked down;
  info.knockback_dir/knockback → collided knockback slide; info.knockdown →
  `knocked_down` state; stun ≥ stagger_damage (10); a creature source
  becomes the target), `receive_shove(source, info)`, `is_winding_up()`,
  `is_knocked_down()`, `die(killer)` → ZombieCorpse.
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

### `ItemData` / `WeaponData` / `ItemInstance` / `WorldItem` (items/, R4)
- `ItemData` (Resource): id, display_name, category, weight, max_stack,
  max_condition (0 = unbreakable), color, world_size. `WeaponData
  extends ItemData`: damage range, crit, head-hit chance, reach, arc,
  max targets, swing time + windup/active fractions, stamina, knockback,
  knockdown (and vs-windup), `is_shove`, condition loss, noise radius.
- `ItemInstance` (RefCounted): data + condition + stack, `wear()` →
  `broken` signal, `to_dict/from_dict`.
- `WorldItem` (StaticBody3D, layer 4, mask 0, group `world_item`):
  blockout box from the data, Interactable "Pick up <name>" →
  duck-typed `actor.pick_up_item(item) -> {ok}`; frees itself on success.
- R6: a bag `WorldItem` also offers "Open <bag>" / "Close": it exposes
  its `contents` as `inventory`, `display_name`, `is_open_for`, and
  delegates `take/put/take_all/put_all` to its own `ContainerAccess`
  (now duck-typed on its container node); closes > 2 m away, on pickup
  or tree exit. Static `WorldItem.drop(inst, actor)` puts an instance at
  the actor's feet under the actor's parent (the map).
- R5: `ItemData.category` is an enum (`Category`: food, drink, medical,
  weapon, tool, material, clothing, container, misc; `category_id()` →
  StringName), `tags`, `description`. Subclasses `FoodData` (calories,
  hunger, thirst, spoil_days, needs_opener — consumed in R7),
  `MedicalData` (bandage_quality, rebleed_chance / rebleed_after,
  disinfectant, pain_relief, splints), `ContainerItemData` (capacity_kg,
  weight_reduction = fraction of the contents' weight removed while
  worn). R6: `WeaponData.two_handed`.

### `ItemDB` (items/item_db.gd, autoload, R5)
- Scans `res://data/items` recursively at startup, indexes `ItemData` by
  id; duplicate ids → `push_error` + `duplicates()`; pure
  `find_duplicate_ids()`. `get_item(id)`, `has_item`, `all_ids`,
  `ids_in_category`, `instance(id, count, condition)`, `register()`.
  No class_name (the autoload name is the global).

### `ItemContainer` (inventory/item_container.gd, RefCounted, R5)
- Pure data: `items: Array[ItemInstance]`, `capacity` (kg, < 0 =
  unlimited). `add(item)` / `add_new(data, n)` / `add_id(id, n)` merge by
  id up to `max_stack` (condition items never stack), refuse "Too heavy"
  unless everything fits; `remove(item, n)`, `remove_id`,
  `transfer_to(to, item, n)` (moves as many as fit; refused only when
  none fit), `transfer_id`, `transfer_all`, `split_stack(item, n)`,
  `can_fit`, `fit_count`, `total_weight`, `grouped()`,
  `to_dict()/from_dict()` (ids via ItemDB). `changed` signal.
- Ownership: every stored `ItemInstance` has a weak `owner_container()`
  back-ref (set / cleared by the container); `add()` refuses an instance
  owned by another container ("Already in another container"); a fully
  merged instance is spent (stack 0). `remove(item, 0)` removes nothing;
  `from_dict` skips counts ≤ 0 and never loads past capacity (warnings).
- R6 perf: cached `total_weight()` (updated incrementally by add /
  remove / transfer, invalidated otherwise), `begin_batch()/end_batch()`
  coalesce `changed`; a stored bag's contents `changed` re-emits here
  (connected on append, disconnected on detach) — recursive.
- R6 nesting: `owner_item()` (weak ref to the bag whose contents this
  is), `equipment_slot` (slot containers), `accept_reason(item)` (cycle
  / worn-bag rules, checked by `add` and `transfer_to`), `fit_item(item)`
  and `fit_count(data, n, unit)` with the instance's `unit_weight()`
  (bags weigh their contents). `ItemInstance`: `contents` (bags),
  `uid` (creation order), `unit_weight()`, `is_bag()`,
  `is_two_handed()`; `to_dict` nests contents.
- Convention: anything holding items exposes it as `inventory`
  (`Player`, `LootContainer`, `ZombieCorpse`); `LootContainer.inventory_of(node)`
  duck-types it.

### Loot (loot/, R5)
- `LootTable` (Resource, data/loot/**.tres; id = relative path):
  `entries [{item_id, weight, min_count, max_count, chance, rarity}]`,
  `rolls_min/max`, `empty_chance`, condition range, `validate()`.
  Rarity tiers common/uncommon/rare/very_rare = ×1/0.6/0.3/0.1 chance.
- `LootResolver` (static, deterministic): `roll(table, rng, world_age)`,
  `age_multiplier` = max(0.2, 1 − age/60), `effective_chance`,
  `pick_weighted`, `seed_for(world_seed, stable_id)`,
  `table_candidates(building, room, container)` (fallback chain).
  The rng is consumed identically whatever a gate decides, so an older
  world only removes items from a container's day-0 contents.
- `LootTableDB` (autoload, like ItemDB): scans data/loot recursively,
  `resolve(b, r, c)`.
- Per roll the main rng draws only the weighted pick and a seed for a
  sub-rng (gate, count, conditions): gate outcomes never shift later
  rolls, so an older world's roll is a sub-multiset of the day-0 roll.

### `LootContainer` (interaction/loot_container.gd, StaticBody3D, R5)
- Layers 1+4 (+6 when ≥ 1.2 m), group `container` + `persistent`.
  Lazily rolls `inventory` on first open (fixed_items + table), seeded by
  world seed + `persist_id` ("HouseA/kitchen/0", "corpse/<spawner path>/<spawn counter>",
  "Map/SupplyCrate"); `searched` flag. "Search <name>" → actor busy
  tween (`begin_busy(&"search")`, 1 s first / 0.5 s later, 3 m sound,
  damage cancels) → `open()` (lid tween, `container_opened`). "Close"
  while open; > `max_open_distance` (2 m, flat distance to its box),
  death, tree exit → `close()` (`container_closed`). `take/put/take_all/
  put_all(actor, …)` emit `item_transferred(from, to, item)` and
  `interaction_refused` reasons. LootContainer is only the interaction
  provider + loot roll + persistence glue: rummaging and the transfer
  rules live in `ContainerAccess` (inventory/, owned RefCounted; outgoing
  items ask the actor's `can_release_item(item)` — the player refuses its
  equipped / swung weapon "Mid-swing"), the look in `ContainerVisual`
  (child "Visual": box + front door / top lid tween) built when `size`
  is set. `ZombieCorpse extends LootContainer`
  (layer 4 only, "Search corpse").
- `WorldConfig` (world/, node "World" in the map, group `world_config`):
  `world_seed`, `world_age_days`, owns a `WorldState` (persist registry:
  snapshot/apply by `persist_id`, pending entries for late nodes; Round
  10 serializes it).

### `LootWindow` (ui/inventory/loot_window.gd, CanvasLayer 2, R5 / R6)
- R6 split: `ItemListPanel` (one panel: title bar, column header,
  pooled rows reconciled by key — item or header — with
  `show_entries(entries)`, `last_rebound`, `row_node/row_for/
  visible_row_count/header_count`; emits row_pressed /
  row_right_clicked / row_hovered; drag via Callables),
  `ItemContextMenu` (PopupMenu, `open_for`, `action_chosen`),
  `InventoryDragDrop` (payload / destination / can_drop / drop). The
  controller keeps the test API, emits
  `EventBus.inventory_screen_toggled(visible)` (PlayerCombatInput
  ignores attack presses while it is open).
- R6: the container side accepts any node with `take/put/take_all/
  put_all/close/is_open_for`, `inventory`, `display_name` (LootContainer
  or a bag `WorldItem`). Player side = tab column (`player_tabs()`:
  main inventory + worn bag; `select_tab(i)`, `active_player_container()`
  is the take target) + list in display order (`side_items(side)`:
  equipped first, then category-grouped with header rows; the container
  side keeps storage order). Rows forward drag data
  (`drag_payload`); panels, lists, rows and tabs accept drops
  (`can_drop_payload / drop_payload(target, data)`, targets `&"player"`,
  `&"container"`, `&"tab_<i>"`). Right-click → PopupMenu from
  `context_actions()` / `perform_context()`; `click_row(side, item,
  shift, ctrl)`; `drop_selected()` (G, `drop_item` action).
  Pooled rows: `row_node(side, i)` = i-th item row (headers skipped),
  `row_for(side, item)`. Note: `set_meta(k, null)` removes a key and
  `get_meta(k, null)` then errors — use `has_meta`.
- Built in code. Top-left panel = player inventory ("Inventory" · Transfer
  All · "W / 15 kg"), top-right = open container (Loot All · name ·
  "W / Cap kg"); rows = stacks (colour square, name, type, ×count, kg,
  cond%), pooled per list and bound to their ItemInstance (not the
  index).
  Click → stack, Shift-click → one; rows that don't fit greyed with a
  "Too heavy" tooltip; footer status line. E / Esc close, Tab toggles the
  player panel alone. Listens to container_opened / closed,
  inventory_changed (deferred refresh), interaction_refused,
  item_transferred. Test API `transfer_index / loot_all / transfer_all /
  rows / row_enabled`.
- `Player.inventory: ItemContainer` (15 kg, `inventory_capacity`);
  `pick_up_item` adds to it; `held_weapons()` / X cycle read it; a
  weapon leaving it is unequipped. `InjuryComponent.bandage_worst()`
  consumes the best dressing from `character.inventory` ("No bandages").

### `Equipment` (inventory/equipment.gd, child `Equipment` of the Player, R6)
- Slots primary_hand / secondary_hand / back as unlimited
  `ItemContainer`s tagged `equipment_slot`; equipped items live there
  (out of the inventory), so generic transfers / the loot window work on
  them and slot changes from anywhere are noticed via `changed`.
- `equip(item, slot)` (slot rules, displaced items stowed into main
  inventory → worn bag, refused as a whole "No room in inventory"),
  `unequip(item|slot)`, `destroy(item)`, `primary()`, `secondary()`
  (two-hander = both), `back_bag()`, `bag_contents()`, `hand_items()`,
  `storage()` (main + worn bag), `owns_container(c)`, `carries(item)`,
  statics `slot_rule()`, `default_slot()`, `can_hold()`,
  `is_equippable()`. Hotbar facade over `hotbar: Hotbar` (pure slot
  bookkeeping, references kept by identity): `assign_hotbar(i, item)`
  (validates), `hotbar_item(i)` (null while not carried), `use_hotbar(i)`,
  `hotbar_summary()`; `hotbar_changed` only when the summary changed.
  `from_dict` routes through `equip()` + combo checks.
- Owner duck-typing: `inventory`, optional `can_release_item(item)`.
- Signals: `equipped_changed(slot, item)`, `contents_changed` (slots,
  main inventory or worn-bag contents changed), `hotbar_changed`;
  EventBus `equipment_changed`, `hotbar_changed`. `to_dict/from_dict`.

### `Encumbrance` (inventory/encumbrance.gd, child `Encumbrance`, R6)
- `mark_dirty()` (the Player, on every carried change) → one deferred
  flush per frame; `recompute()` flushes now; `state` / `weight` getters
  flush when dirty; `emit_count` for tests. Per flush:
  weight → state (ok / light / heavy / overloaded from the profile's
  Carrying group) → movement modifier `encumbrance`, stamina drain
  multiplier, footstep multiplier, sprint lock; `encumbrance_changed`.
  Pure statics `carried_weight(main, hands, worn_bags)`,
  `worn_bag_weight(bag)`, `state_for(w, cap, heavy, over)`,
  `effects_for(state, profile)`, `state_label()`.

### `ItemActions` (inventory/item_actions.gd, RefCounted statics, R6)
- `for_item(actor, item)` → context-menu entries `{id, label, enabled,
  reason}`; `perform(actor, item, id)` → the Player verbs
  (`equip_item`, `unequip_item`, `use_item`, `drop_item`, `split_item`)
  or `Equipment.assign_hotbar`. `use_block_reason(data)` (food / drink
  → "… comes in Round 7").

### Player carrying verbs (player/player.gd, R6)
- `pick_up_item`, `equip_item`, `unequip_item`, `move_item(item, to,
  n)` (between own containers), `drop_item(item, n)` (→
  `WorldItem.drop`, `item_dropped`), `split_item`, `use_item`,
  `use_hotbar(i)`, `cycle_weapon()`, `carries`, `owns_container`,
  `carried_storage()`, `carried_weight()`, `carried_to_dict /
  carried_from_dict`. Refusals → `interaction_refused(player, null,
  reason)` (HUD + window footer).

### `MeleeCombat` (combat/melee_combat.gd, child `Combat`, R4)
- Facade for any Character over two RefCounted helpers:
  `SwingStateMachine` (pure: phases IDLE → CHARGING → WINDUP → ACTIVE →
  RECOVERY, charge time, one-deep queue; `finish()` returns the queue
  snapshot and always clears it; static `charge_multiplier()`) and
  `HitResolver` (target query + LOS, damage / crit / head / knockback /
  knockdown / shove, `wear()` of the swung ItemInstance, `melee_hit` +
  sound; statics `select_targets()`, `stamina_damage_multiplier()`).
  Tuning: `CombatProfile` (data/combat/).
- API `start_attack()/release_attack()/attack_now(held)/shove()/
  cancel_charge()/set_aiming()/equip()/charge_fraction()/
  pain_modifiers()`, settable `aim_direction`, `scripted`.
- R6: `equipped` mirrors the actor's `Equipment` primary hand
  (`equipped_changed`); `equip(item)` asks the Equipment (returns its
  {ok, reason}); actors without Equipment keep direct assignment.
- Targets: sphere query on `target_mask` (layer 3) → `select_targets` →
  LOS ray (1+7+8) at `hit_height`. Duck-typed targets: `take_damage(amount, source,
  info)`, optional `receive_shove(source, info)`, `is_winding_up()`,
  `is_dead()`.
- Sets movement modifiers `charge` / `attack` and
  `Character.facing_override` (aim / swing direction); pays stamina via
  `StatsComponent`; calls `actor.on_weapon_broken(item)` if present.
- Local signals for presentation (`swing_started`, `active_started`,
  `swing_finished`, `equipped_changed`, `aim_changed`) + EventBus events.
- `PlayerCombatInput` (player/): input → MeleeCombat / InjuryComponent;
  static `ground_point(camera, screen_pos, plane_y)` (ortho-safe mouse →
  ground). `PlayerController` caps the mode at walk while aiming.
- `MeleeVisuals` (combat/, child `CombatVisuals`): weapon box on the body
  visual (sweeps through the arc), aim ring + arc preview, active-window
  arc; listens to the local signals only.

### `InjuryComponent` / `Injury` (injuries/, child `Injuries`, R4)
- `Injury` (RefCounted): `Region` (10) / `Type` (6) enums + StringName
  ids used in payloads and data, bleeding / bleed_left / heal_left /
  bandaged / infected, `to_dict()`, pure `roll_weighted(weights, r)`.
- `InjuryComponent`: `setup(character)` is called by `Character._ready`
  (registers stats `pain`, `infection`, connects `health.damaged` and
  `window_climbed`). `add_injury()`, `bandage_worst()` (4 s busy tween
  owned by the Character), `tick(dt)` at `profile.tick_hz` (tests call it
  to fast-forward). Pure statics `total_bleed_rate`, `total_pain`,
  `leg_speed_multiplier`, `max_stamina_penalty`, `pain_combat_modifiers`,
  `infection_stage_for`. `interrupt_bandage()` (on any damage),
  `bandage_progress()`. Effects: health drain,
  movement modifier `injury`, `StatsComponent.set_max(stamina)`, pain
  stat, infection stat.
- Data: `InjuryProfile` (data/injuries/) with one `InjuryTypeSpec`
  sub-resource per type, region weights, treatment and effect numbers.

### `BloodDecals` (effects/blood_decals.gd, node in the map, R4)
- One MultiMesh (200 flat discs), ring buffer; listens to `melee_hit`,
  `character_damaged`, `blood_spilled`. Group `blood_decals`.

### `HealthComponent` (characters/health_component.gd)
- `max_health`, `take_damage(amount, source, info) -> {ok, health, dead}`,
  `heal`, `revive`, `invulnerable`; local `damaged`/`died`/`changed` and
  EventBus `character_damaged` / `character_died` with the owning
  character. `Character` picks up an optional `Health` child, delegates
  `take_damage`, and on death sets `is_busy` (input ignored).
- R4: `drain(amount, source, cause)` for bleeding / infection (no
  `damaged` signal → no hit flash, no new wound); every change emits
  `EventBus.health_changed`. `StatsComponent.set_max(id, max)` lets
  injuries lower max stamina.

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
Round 4: `health_changed(character, value, max)`,
`injuries_changed(character, summary)`, `bandage_started(character,
region, seconds)`, `bandage_finished(character, region)`,
`blood_spilled(position, amount)`, `melee_swing(actor, weapon_id,
charge)`, `melee_hit(actor, target, damage, info)`,
`attack_refused(actor, reason)`, `melee_aim_changed(actor, aiming,
in_reach)`, `weapon_equipped / weapon_condition_changed /
weapon_broken(actor, item)`, `item_picked_up(actor, item)`,
`zombie_knocked_down(zombie, source)`, `zombie_got_up(zombie)`,
`bandage_interrupted(character, region)`,
`infection_stage_changed(character, stage)`.
Round 6: `inventory_screen_toggled(visible)`, `equipment_changed(character, slot, item)`,
`hotbar_changed(character, slots)`, `encumbrance_changed(character,
state, weight)`, `item_dropped(character, item)`.
Round 5: `inventory_changed(owner)`, `container_opened(actor,
container)`, `container_closed(actor, container)`, `item_transferred(from,
to, item)`, `timed_action_started(actor, action, label, seconds)`,
`timed_action_finished(actor, action, completed)`,
`wound_reopened(character, region)`.

## Physics layers
1 world · 2 player · 3 zombies · 4 interactables · 5 items · 6 occluders ·
7 doors · 8 window_panes

World items (`WorldItem`): layer 4, mask 0. Loot containers /
furniture (R5): 1+4 (+6 when tall); plain furniture 1 (+6); corpses 4. Melee target query: layer 3;
melee LOS: 1+7+8. Walls: 1+6. Windows: sill + header body 1+4+6, glass child body 8 while
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
`world_item` (R4; dropped items and bags on the ground too, R6), `blood_decals` (R4), `container`, `persistent`,
`furniture`, `world_config` (R5),
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
