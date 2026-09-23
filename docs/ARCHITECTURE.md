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
  debug flags. `TimeManager` (R7) owns world time; `SoundManager` (R8)
  owns gameplay sound propagation; `SaveManager` (R10) owns save / load
  orchestration; future managers (`WorldManager`) are separate autoloads
  with single responsibilities.
- **Data-driven content** (from Round 5 on): items, loot tables, recipes,
  zombies as `Resource` files under `data/`.

## Folder layout (current)

```
core/         event_bus.gd, game_manager.gd             (autoloads)
              time_manager.gd (autoload TimeManager), game_clock.gd (GameClock) (R7)
              save_manager.gd (autoload SaveManager), save_file.gd (SaveFile),
              save_schema.gd (SaveSchema), saveable.gd (Saveable) (R10)
audio/        sound_manager.gd (autoload SoundManager), sound_event.gd (SoundEvent),
              sound_category.gd (SoundCategory), sound_category_table.gd (SoundCategoryTable),
              sound_math.gd (SoundMath), spatial_hash.gd (SpatialHash) (R8)
characters/   character.gd, movement_component.gd, stats_component.gd,
              health_component.gd, footstep_emitter.gd, body_helpers.gd (R3),
              shout_component.gd (ShoutComponent) (R8)
characters/models/  outfit.gd (Outfit), appearance.gd (Appearance), humanoid_builder.gd
              (HumanoidBuilder), character_animations.gd (CharacterAnimations),
              character_model.gd (CharacterModel), character_animator.gd
              (CharacterAnimator), character_assets.gd (CharacterAssets) (R8.5)
vehicles/     vehicle_data.gd (VehicleData), vehicle_builder.gd (VehicleBuilder),
              vehicle.gd (Vehicle), vehicle_container.gd (VehicleContainer),
              vehicle_assets.gd (VehicleAssets) (R8.5)
player/       player.gd, player.tscn, player_controller.gd, player_interaction.gd,
              player_combat_input.gd (R4)
camera/       isometric_camera.gd, occlusion_manager.gd
interaction/  interactable.gd, wall_fixture.gd, door.gd, window.gd (R2), loot_container.gd, container_visual.gd (R5),
              rest_furniture.gd (RestFurniture), sink.gd (Sink) (R7), glass_shards.gd (GlassShards) (R8),
              barricade_component.gd (BarricadeComponent), furniture_work.gd (FurnitureWork),
              timed_work.gd (TimedWork) (R9)
skills/       skill_component.gd (SkillComponent) (R9)
survival/     needs_component.gd (NeedsComponent), needs_math.gd (NeedsMath), consume_action.gd
              (ConsumeAction), rest_component.gd (RestComponent), danger.gd (Danger) (R7)
buildings/    building.gd, room.gd, building_plan.gd, house_blockout.gd (R2), furniture_catalog.gd (R5),
              barricade_data.gd (BarricadeData) (R9)
ai/           state_machine/state_machine.gd, state.gd  (generic FSM, R3)
items/        item_data.gd, weapon_data.gd, item_instance.gd, world_item.gd (R4),
              food_data.gd, medical_data.gd, container_item_data.gd, item_db.gd (autoload ItemDB) (R5)
inventory/    item_container.gd (ItemContainer), container_access.gd (ContainerAccess) (R5),
              equipment.gd (Equipment), hotbar.gd (Hotbar), encumbrance.gd (Encumbrance), item_actions.gd (ItemActions) (R6),
              carried_items.gd (CarriedItems) (R9)
loot/         loot_table.gd, loot_table_db.gd (autoload LootTableDB), loot_resolver.gd (R5)
combat/       melee_combat.gd, swing_state_machine.gd, hit_resolver.gd, melee_visuals.gd (R4)
injuries/     injury.gd, injury_type_spec.gd, injury_component.gd (R4)
effects/      blood_decals.gd (R4), noise_rings.gd (NoiseRings) + noise_ring.gdshader,
              sound_debug_overlay.gd (SoundDebugOverlay) (R8), splinters.gd (Splinters) (R9)
zombies/      zombie.gd/.tscn, zombie_visual.gd, zombie_corpse.gd, zombie_senses.gd,
              zombie_ai.gd, zombie_spawner.gd, states/zombie_state_*.gd (R3; climb_window R9)
world/        blockout_box.gd, nav_baker.gd, world_query.gd (R3), world_config.gd, world_state.gd (R5),
              entry_planner.gd (EntryPlanner) (R9), world_snapshot.gd (WorldSnapshot) (R10),
              day_night_lighting.gd (DayNightLighting) (R7)
ui/hud/       hud.gd, hud.tscn, damage_vignette.gdshader, hotbar.gd (HotbarWidget, R6),
              clock_widget.gd (ClockWidget), moodle_list.gd (MoodleList) (R7),
              noise_meter.gd (NoiseMeter) (R8)
ui/menus/     main_menu.gd/.tscn (MainMenu, the main scene), pause_menu.gd (PauseMenu),
              slot_browser.gd (SlotBrowser), menu_style.gd (MenuStyle) (R10)
ui/inventory/ loot_window.gd/.tscn (LootWindow controller), item_list_panel.gd (ItemListPanel),
              item_context_menu.gd (ItemContextMenu), inventory_drag_drop.gd (InventoryDragDrop) (R5/R6)
worldgen/     world_gen_params.gd (WorldGenParams), world_layout.gd (WorldLayout),
              world_generator.gd (WorldGenerator), building_plan_generator.gd
              (BuildingPlanGenerator), world_layout_validator.gd (WorldLayoutValidator),
              world_map_renderer.gd (WorldMapRenderer), world_builder.gd (WorldBuilder),
              world_nav.gd (WorldNav) (R11)
maps/         world.tscn (R11: the generated county; main-menu New game),
              test_ground.tscn (the hand-made systems test map)
data/         characters/*.tres, buildings/{house_a,shed_a,furniture_catalog}.tres, zombies/zombie_basic.tres,
              items/<category>/*.tres (41 items, R5), loot/*.tres + loot/garage/*.tres (R5),
              combat/combat_profile.gd + .tres, injuries/injury_profile.gd + human_injuries.tres (R4),
              world/time_config.gd + .tres, survival/needs_profile.gd + .tres (R7),
              audio/sound_categories.tres (R8), characters/outfits/*.tres (14 outfits),
              vehicles/*.tres (6 vehicle types), loot/vehicle_trunk + vehicle_glovebox (R8.5),
              barricades/wood_planks.tres (R9), worldgen/default_world.tres (R11),
              loot/{store_shelf,desk}.tres + loot/{convenience_store,hardware_store,pharmacy,
              gas_station,diner,warehouse,barn}/*.tres (R11)
assets/       materials/grid_ground.gdshader, world_ground.gdshader, tree_canopy.gdshader (R11)
tests/        test_runner.gd, test_case.gd, unit/, integration/, perf/, screenshot_run.gd,
              tools/ (dev previews: model_preview.gd, street_preview.gd; R11:
              world_map_preview.gd, world_validate.gd, world_probe.gd — not tests)
scripts/      test.sh, screenshots.sh, perf.sh
docs/
```

Planned folders follow the brief (`crafting/`, `simulation/`,
`farming/`, `weather/`, `electricity/`, `npc/`).

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

- R7: `busy_cancelled(context)` signal + `cancel_busy(context)`: the
  single way a busy action ends early (override by `begin_busy`, cancel,
  death); owners (ConsumeAction, InjuryComponent bandage, ContainerAccess
  search, RestComponent) restore their state in the handler.
- R7: max stamina = `combined_max(base, penalties, multipliers)` —
  `set_stamina_max_penalty(source, pts)` (InjuryComponent `injury`) and
  `set_stamina_max_multiplier(source, m)` (NeedsComponent `needs`);
  `set_swing_time_multiplier(source, m)` / `swing_time_multiplier()`
  (MeleeCombat multiplies it into the swing with pain). Optional `needs`
  child ("Needs") set up in `_ready` after injuries.

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
- R7: `set_regen_multiplier` / `regen_multiplier()` scale POSITIVE rates
  (fatigue slows stamina recovery). Busy contexts `eat`, `sleep` (idle
  rate) and `rest` (idle × `stamina_rest_multiplier`) in the profile.

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

### Barricades / carpentry (R9)
- `BarricadeData` (Resource, data/barricades): plank health / max planks
  per kind / tools / materials / seconds / noises / removal specs /
  attacker slots / sound factor / vision threshold / nav cost; pure
  `missing_reason`, `remove_yield`, `build_seconds_for`,
  `plank_health_for`, `sound_factor`, `vision_blocked`, `color_for`,
  `validate`.
- `BarricadeComponent` (Node3D child "Barricade" of a Door /
  HouseWindow; `of`, `ensure`, `planks_on`): `planks [{health, max,
  tilt}]` (last = outermost), `side`, `add_plank(health, side)`,
  `remove_plank()`, breakable `take_damage` / `blocks_path` /
  `interaction_prompt_position`, attacker slots `claim_attacker` /
  `release_attacker` / `attacker_count`, statics `actions_for(fixture,
  actor)` / `perform(fixture, id, actor)` (the fixture appends / routes
  them), `start_nailing` / `start_prying` (TimedWork), board meshes under
  the fixture's Visual, inner `PlanksBody` (pane layer, ≥ 2 planks),
  `entry_score` (pure), `to_dict/from_dict`. Fixture hooks (WallFixture
  base + Door / HouseWindow): `barricade_kind`, `barricade_opening`,
  `barricade_block_reason`, `on_barricade_changed`, `barricade_planks`,
  `is_barricaded`, `sound_barricade_factor`, `breakable_target`.
- `HouseWindow` R9: breakable (group, `take_damage` → planks or pane →
  smash, `blocks_path`), `nav_link: NavigationLink3D` (exterior only) with
  `nav_cost()`, `approach_point(p)`. `Door` R9: `blocker` (furniture),
  `furniture_blocker()`, `wall_thickness`, open refused "Barricaded" /
  "Blocked by furniture", `take_damage` routes to planks.
- `TimedWork` (RefCounted, owned by whoever starts it; ConsumeAction too):
  one busy action with completion / cancel callbacks — the single cancel
  implementation (damage, move intent, `cancel_for(actor)` from the
  player's Esc / E / action keys, `busy_cancelled`), repeated noise,
  `action_id` for `timed_action_started/finished`; statics `is_busy`,
  `running_for`, `cancel_for`.
- `EntryPlanner` (world/, static + per-building opening cache): `score`,
  `window_link_cost`, `openings(building)`, `entry_score_of`,
  `better_entry`, `building_of`. Used by `HouseWindow.nav_cost()` and
  `ZombieAI.consider_detour()`.
- `NavBaker` R9: `request_rebake()` / static `request_rebake_in(tree)`
  (coalesced async re-bake, `rebaked` signal, `rebake_count`; `baked`
  stays true), group `nav_baker`.
- `FurnitureWork` (Node3D child of a container / RestFurniture / Sink,
  group `interaction_extension`): "Block door" / "Move back" /
  "Disassemble"; breakable while blocking (layer 9); pure `yield_for`.
  Built by `HouseBlockout._add_furniture_work` from catalog keys.
- `Interactable` R9: extensions — children of the provider in group
  `interaction_extension` add actions (`_sources()`); actions may be
  `explicit` (never the E default: `is_default_candidate`).
- `ItemActions` R9: `OPEN_BOX`, `is_box`, `open_box` (ItemData
  `unpack_item` / `unpack_count`). `PlayerInteraction` R9:
  `is_cancel_event`, `cancel_work`.
- `CarriedItems` (static): `containers`, `find_tool(actor, tags)`,
  `count`, `consume` (all-or-nothing), `give` (drops the overflow).
- `SkillComponent` (Node "Skills" on the Player): `xp`, `add_xp`,
  `level`, `set_level`, carpentry multipliers, statics `level_for_xp`,
  `xp_for_level`, `carpentry_time_multiplier`,
  `carpentry_health_multiplier`; `to_dict/from_dict`.
- `ZombieAI` R9: `resolve_breakable(collider)` (breakable_target / group
  / breakable child), `window_link_ahead()` (path link owned by a window,
  goal across it), `window_transition()`, `obstacle_transition()`,
  `consider_detour()` / `goal_or_detour()` / `detour_active()`,
  `reset_path()`, `in_crowd()`, `obstacle_ahead()` (3 m when stuck);
  attack_door queues slotless zombies; `Zombie.start_climb / stop_climb / is_climbing /
  climb_progress`; state `ZombieStateClimbWindow`; attack_door claims
  obstacle slots. Obstacle ray mask 7 + 9.
- `OcclusionManager.forget_meshes(n)` (planks added under a cached
  fixture). `SoundManager.obstacle_attenuation(from, to, skip_fixture)`
  multiplies each hit fixture's barricade factor once;
  `barricade_fixture_of(collider)`; openings carry `factor`.

### Save / load (R10)
- `Saveable` (core/, statics): the contract — group `saveable`,
  `persist_id`, `save_state()` (carries a `kind`) / `load_state(d)`,
  optional `remove_for_load()`; `collect(tree, root)`; JSON helpers
  `vec3` / `to_vec3`, `xform` / `to_xform`, `finite_or`. Implemented by
  LootContainer (not corpses), Door, HouseWindow (`WallFixture.persist_id`),
  FurnitureWork. Ids are `<building>/<plan entry id>` from BuildingPlan
  data (`BuildingPlan.id_problems()` checks presence / uniqueness;
  `HouseBlockout._entry_id` falls back to build order only for id-less
  test plans). Destroyed statics: `WorldConfig.destroyed_ids` /
  `mark_destroyed` / static `record_destroyed(node)`.
- `SaveSchema` (core/): `check(data) -> ""|"Corrupt save (path: why)"`,
  the full typed check of a snapshot (phase 1 of every load).
- `SaveFile` (core/, statics): `VERSION`, `migrations`, `root` (ROOT /
  TEST_ROOT), `is_valid_slot`, `encode_slot` / `decode_slot` (injective),
  `slot_dir` / `world_path` / `meta_path`, `allowed_maps` / `allowed_map`,
  `to_json`, `parse`, `migrate`, `validate` (= SaveSchema.check),
  `decode`, `write_atomic`, `read_text`, `list_slots` (typed meta),
  `meta_num` / `meta_str` / `meta_dict`, `delete_slot`,
  `first_difference`.
- `WorldSnapshot` (world/, statics): `capture(map)`, `summary`,
  `apply_static(map, data, index)` (statics + destroyed list, before the
  bake), `apply_dynamic(map, data)` (synchronous; `index_items` /
  `find_item(uid)` for hotbar ghosts), `player_of`, `spawners_of`.
- `SaveManager` (autoload, PROCESS_MODE_ALWAYS): `save_game(slot, map)`,
  `load_game` / `load_data` (two-phase coroutines), `read_slot`,
  `has_slot`, `list_slots`, `delete_slot`, `save_block_reason`,
  `autosave_block_reason`, `unsaved_minutes`, `request_load`,
  `request_quit_to_menu`, `quit_to_menu`, `new_game` /
  `instantiate_new_game(map, seed)`, `confirm(text, on_yes)` /
  `answer(yes)` / `is_confirming` / `confirm_text`, `show_loading` /
  `is_loading_shown` (its own CanvasLayer "SaveOverlay", layer 50),
  `find_saveable`, `current_map`, F9 / F10 (`quick_slot`), autosave.
- Records: `Player.save_state / load_state`, `Zombie.save_record /
  apply_record`, `ZombieSpawner.save_state / load_state / restore_zombie`
  (+ `near_count` / `near_center` / `near_radius` /
  `near_min_player_distance`), `ZombieCorpse.save_record / restore`,
  `ZombieProfile.registry / by_id / id_of`, `HealthComponent.to_dict /
  from_dict`, `Injury.save_dict / from_save`, `InjuryComponent.to_dict /
  from_dict` (+ `restoring`), `BloodDecals.to_dict / from_dict`,
  `IsometricCamera.view_state / restore_view`, `ItemInstance` uid in
  `to_dict / from_dict`, `Equipment` hotbar refs `{uid}`,
  `WorldConfig.prepare_new_game / player_start / starter_items /
  last_saved_minute`.
- UI: `PauseMenu` (Resume / Save / Load / Quit; `browser: SlotBrowser`),
  `MainMenu` (`continue_button`, `browser`), `SlotBrowser` (VBox: `open(mode)`,
  `save_new`, `ask_overwrite`, `ask_delete`, `load_slot`, `name_edit`,
  `list_box`, `status`), `MenuStyle` (`slot_text` type-safe). HUD:
  `game_notice`, `game_loaded` (resync).
- Items: `ItemData.tear_into / tear_count`, `ItemActions.TEAR /
  is_tearable / tear`. Zombies: `ZombieProfile.window_land_down_seconds`,
  `ZombieAI.down_seconds`, `knock_down(source, seconds)`;
  `HouseWindow.WINDOW_NAV_LAYER` (links on navigation layer 2; zombie
  agents 1 + 2).

### World generation (worldgen/, R11)
- `WorldGenParams` (Resource, data/worldgen): sizes (384-2048 m), noise,
  road widths, `road_wiggle`, town blocks / rows / lots, hamlet / farm
  counts, population + rural group sizes; `area_scale()`,
  `scaled_range(lo, hi, floor)`, `effective_route_cell()`, `validate()`.
- `WorldLayout` (RefCounted, pure data): `version`, zones raster +
  records. Area records are **oriented boxes**: `xf: Transform2D` (local →
  world, rotation only) + `size`, `rect` = world AABB (lots: x along the
  front edge, y away from the road). Roads (`points`, `width`,
  `sidewalk`, `cap`), `junctions`, settlements, lots, buildings (`xf`,
  `size`, `local`, `door`, `door_x`, `access`, `access_path`), paths,
  parking, fields (`axis`, `crop`), fences, ponds, props, vehicles (`yaw`:
  forward = (sin, cos)), trees, zombies, `zombie_groups`, chunk_density,
  spawn, `plans` (not serialized). Geometry helpers: `obb_poly`,
  `poly_of`, `poly_aabb`, `obb_has_point`, `rec_has_point`, `polys_overlap`,
  `seg_poly_distance`, `polyline_poly_distance`, `vehicle_poly`; chunk
  helpers; `to_dict` / `to_json`, `layout_hash()` (cached; excludes the
  version), `plan_hash()`.
- `WorldGenerator` (RefCounted): `VERSION`, static `generate(seed,
  params)` (cached), `generate_fresh`, `sub_seed(seed, tag)` (one rng per
  stage), `frame_rec`, `rot90`. Routing: AStarGrid2D, road cells solid
  (`_mark_road_cells`), `_route(a, b, allow_cross, wiggle)`,
  `_split_crossings`, `_runs_along(_crossing)`, `_insert_junction`.
  Debug counters `stats.rej_*`.
- `BuildingPlanGenerator` (RefCounted): static `generate(kind, seed,
  opts)` (opts: `garage`, `hamlet`, `hammer`, `max_width`, `max_depth`),
  `rotate_plan`, `opening_point`, `opening_outward`, `exterior_doors`,
  `check(plan)`; `KINDS` (+ bar, church, post_office). Buildings are
  placed by node transform (HouseBlockout rotates its plan normals to
  world space: `outward` is a world vector).
- `WorldLayoutValidator` (static): `all_problems` (with plans),
  `layout_problems` (fast), `overlap_problems`, `road_problems`,
  `vehicle_problems`, `prop_problems`, `connectivity_problems`,
  `door_problems`, `content_problems`, `plan_problems`,
  `exterior_door_segments`.
- `WorldMapRenderer` (static): `render(layout, mpp, detail) -> Image`,
  `side_by_side(images)`.
- `WorldBuilder` (Node3D "Generated", groups `world_builder`,
  `light_budget`): `generate_and_build()`, `build()`, `layout`,
  `layout_hash()`, `chunks`, `buildings`, `start_position()`,
  `update_lights()` + `light_chunk_radius` / `light_far` /
  `shadowed_lights` / `light_stats`, static `olive(c)`, `splat_image`.
- `WorldNav extends NavBaker` (node "NavRegion"): `radius` 2,
  `keep_radius` 4, `lookahead` 4 s, `max_parallel` 2, `border` 2.4,
  `verify_timeout_frames`; `regions`, `focus_on`, `wanted_chunks`,
  `bake_now`, `request_rebake`, `baked_chunks`, `regions_verified(list)`,
  `chunk_ready(c)`, signal `chunk_regions_changed`; stats `freed_count`,
  `verify_frames`, `max_alive`, `apply_usec`. No coroutines.
- `NavBaker._match_map_cells()` sets the navigation map's cell size /
  height to the region's (world.tscn: 0.1 / 0.1, agent radius 0.2).
- Hooks: `ZombieSpawner.spawn_points` / `groups` / `groups_spawned`
  (saved), `WorldConfig.worldgen_params`, `loot_food_multiplier`,
  static `rng_seed_for(node, tag)`; `WorldSnapshot.capture` writes
  `world.worldgen = {version, layout_hash}`; `SaveManager.check_worldgen(data)`
  (phase 1 of a load); `SaveSchema` checks both; `DayNightLighting` calls
  group `light_budget`; `MainMenu` seed field; input `toggle_map` (M).
- Tools / scripts: `scripts/worldgen_sweep.sh`, `tests/tools/world_*.gd`,
  `tests/integration/slow_frames.gd` (artificial load helper).

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

### `ZombieVisual` (zombies/zombie_visual.gd, Node3D — R8.5)
- Child "Model" = `CharacterModel` with `CharacterAssets.zombie_appearance(ai_seed)`.
  Facing lerp (`update`, only while `needs_update()`), eye mood material
  (`set_tint`, `head_material()` = the eyes), `lunge` (scrubs z_attack +
  offsets the model), `flash` (bite → grab), `hit_flash` (override
  material + z_hit), `set_knocked_down`, `is_lying()` (hips pose),
  `collapse()` (death; then its own `_process` finishes the fall),
  `clip()`. `animate(delta)` is called by `Zombie._physics_process` every
  tick and advances the AnimationPlayer at the LOD divider; pure
  `clip_for(state, speed)`.

### `ZombieCorpse` (zombies/zombie_corpse.gd, StaticBody3D)
- Layer 4 / mask 0, group `corpse`, adopts the zombie's Visual (model in
  its death pose) and is a LootContainer ("Search corpse"). `take_damage`
  refuses.

### Character models (characters/models/, R8.5)
- `Outfit` (Resource, data/characters/outfits): garment colours + style
  flags + `zombie_weight`, `validate()`.
- `Appearance` (RefCounted): outfit, skin, hair, zombie decay (blood,
  torn sleeves, pattern seed), height scale; `random(seed, outfits,
  zombie)`, `key()` (mesh cache key), `zombie_skin()`.
- `HumanoidBuilder` (RefCounted, pure): `BONE_NAMES / BONE_PARENTS /
  BONE_HEADS`, `build_skeleton()`, `build_skin()`, `build_mesh(app)` (2
  surfaces: SURFACE_BODY vertex colour, SURFACE_EYES), `triangle_count()`.
- `CharacterAnimations` (RefCounted, pure): `build_library()`,
  `DESIGN_SPEED`, pose helpers.
- `CharacterModel` (Node3D): builds Skeleton3D / "Body" MeshInstance3D
  (shared mesh + Skin) / AnimationPlayer (MANUAL); `setup(app)` (or the
  exported outfit / skin / hair for hand-placed models), `play`,
  `advance`, `finish`, `set_eye_material`, `set_override`, `attach(bone)`,
  `bone_global_position`, `bone_pose_rotation`.
- `CharacterAnimator` (Node, child "Animator" of a Character): picks the
  clip from death / busy context / MeleeCombat phase / damage /
  locomotion each physics tick and advances the model; worn bag on the
  chest bone (Equipment `equipped_changed`). Pure `locomotion_clip`,
  `busy_clip`, `swing_clips`.
- `CharacterAssets` (Node "CharacterAssets" under the root, added deferred;
  `CharacterAssets.of(tree)`): Skin, AnimationLibrary, body / eye / hit
  materials, outfit pool, typed mesh cache, 48 stratified zombie looks;
  pure `stratify`, `variant_for_seed` (hash), `height_for_seed`.
- `VehicleAssets` (Node "VehicleAssets", `VehicleAssets.of(tree)`): typed
  mesh cache per (data id, seed), `material(surface, lit)`.
- `ZombieSpawner.next_seed(rng)`: the per-zombie seed (static, tests).
- `MeleeVisuals`: with a model, `weapon_pivot` lives on
  `model.attach(&"hand_r")` (`on_hand_bone`), no procedural sweep.

### Vehicles (vehicles/, R8.5)
- `VehicleData` (Resource, data/vehicles): shape, dimensions, cabin,
  palette / livery / light bar, wear chances, storage, `lights_at_night`,
  `validate()`.
- `VehicleBuilder` (RefCounted, pure): `build_mesh(data, seed)`,
  `variation_for`, `axles`, `collision_size`, `triangle_count`; mesh meta
  `surfaces` {name: index}.
- `Vehicle` (StaticBody3D, layers 1 + 6, groups `vehicle` + `occluder`):
  Visual/Body mesh, box collider, `trunk` / `glovebox`
  (`VehicleContainer`), `set_night_lights(night)`, `lights_on`,
  static `material(assets, surface, lit)`.
- `VehicleContainer extends LootContainer`: layer 4 only, own small box,
  `prompt_offset`, container types `vehicle_trunk` / `vehicle_glovebox`.

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
  snapshot/apply by `persist_id`, pending entries for late nodes; the
  Round-10 save uses the `saveable` group + WorldSnapshot instead).

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
- Child of a Character; once per second while it moves calls
  `SoundManager.emit_sound(footstep_<mode>)` (2 / 4 / 8 / 14 m from the
  category data) × `radius_multipliers` (encumbrance).

### Sound (audio/, R8)
- `SoundManager` (autoload, no class_name): `emit_sound(category,
  position, source, overrides) -> SoundEvent` (overrides: radius /
  intensity / duration; other keys → `event.extras`, e.g. a moan's
  `lure` + `hops`). Emits `EventBus.sound_emitted` (UI / sleep / debug)
  and dispatches synchronously to registered listeners found through a
  `SpatialHash` (8 m cells, listener ears refreshed at 5 Hz, query
  widened by 2 m). `evaluate(event, ear, sensitivity, ctx, ear_building)`
  → {slack, attenuation, path}; `obstacle_attenuation(from, to)` (one
  ray re-cast past each hit, ≤ 5, layers 1+7+8, hit_from_inside);
  `queue_sound()` (≤ 2 per frame), `building_at()`; `classify(collider)` (fixtures answer
  `sound_obstacle_kind()`); `ambient_masking` (weather hook);
  `active_events()`, `recent_hearings()`, `stats`, `sound_dispatched`
  signal, `register_listener / unregister_listener / prune /
  listener_count / hashed_count`.
- Listener contract (duck-typed; `ZombieSenses` implements it):
  `sound_ear_position()`, `sound_sensitivity()` (0 = deaf now),
  `sound_owner()` (own sounds skipped), `on_sound(event, info)`.
- `SoundMath` (pure statics): obstacle factors, `attenuation(kinds)`
  (min 0.15), `effective_radius`, `slack`, `via_opening_slack`,
  `perceived`, `should_retarget`, `on_outward_side`.
- `SoundEvent` (RefCounted): id, category, position, radius, intensity,
  duration, created_minute / created_time, extras, weak `source()`.
- `SoundCategory` / `SoundCategoryTable` resources
  (`data/audio/sound_categories.tres`).
- `WallFixture` sound API: `sound_passes()` (open door / open or smashed
  window), `sound_opening_center()`, `sound_obstacle_kind()`,
  `wall_normal()`, `sound_position(actor)` (0.3 m to the actor's side).
- `RestComponent` is a listener while asleep (wake by strength).
- Visuals: `NoiseRings` (map node, pool of 20 shader rings, player
  sounds only), `SoundDebugOverlay` (map node, ImmediateMesh, F4 →
  `GameManager.sound_debug`), HUD `NoiseMeter`.

### `TimeManager` (core/time_manager.gd, autoload, R7) / `GameClock`
- `minutes` (game minutes since the start instant), `config: TimeConfig`,
  `speed_step` (0 pause … 3 = 4×), `sleeping`. Queries `now()`, `hour()`,
  `minute()`, `hour_float()`, `day_index()`, `date()`, `month()`,
  `season()`, `clock_text()`, `date_text()`, `temperature_f()`.
- `advance(m)` (emits `time_advanced` + whole-unit signals),
  `set_minutes` / `set_time_of_day` (jump, not simulated), `set_speed`
  / `request_speed` (danger-gated fast-forward; pause = tree.paused),
  `begin_sleep` / `end_sleep`, `reset()`, `to_dict/from_dict`, `epoch`
  (bumped by reset / load: item ages re-stamp). Resets to 1× on the
  player's death.
  PROCESS_MODE_ALWAYS; handles the time_* input actions.
- `GameClock`: pure statics (minute_of_day, hour_of, days_elapsed,
  date_after, season_of, format_time/date, temperature_c, c_to_f).

### Survival (survival/, R7)
- `NeedsComponent` (child "Needs"): `setup(character)` registers stats
  hunger / thirst / fatigue / sickness; listens to `time_advanced`,
  simulates whole game minutes (`advance_minutes`), `levels`, `effects`,
  `sleeping` / `resting` flags, `consume(effect)`, `set_need`,
  `moodles()`, `can_sleep()`, `to_dict/from_dict`.
- `NeedsMath` (pure): `level_for(value, current, thresholds,
  hysteresis)`, `effects_for(levels, profile)`, `rate_per_hour(need, …)`,
  `consume_effect(food, portion, spoil_state, profile)`, `can_sleep`.
- `ConsumeAction` (child "Consume"): `options_for(item)`, `start(item,
  portion)`, `interrupt()`, `drink_water(amount, s)`,
  `fill_containers(s)`, `fillable_items()`, static `resolve_tool(food,
  containers)`, `action_label()`. Busy context `eat`; the item is out of
  its container while being eaten and is returned on interruption.
- `RestComponent` (child "Rest"): `sleep_block_reason()`, `sleep(bed)`,
  `wake(reason)`, `rest_block_reason()`, `rest(seat)`, `stop_rest()`.
- `Danger` (static): `chasers`, `is_chased`, `nearest_zombie_distance`,
  `threat_reason(tree, target, radius)` — duck-typed zombies (`zombie`
  group, `hostile`, `target`).
- Data: `FoodData` gains fresh/rotten days, eat seconds, tool tags,
  empty item; `ItemData.fill_item_id`; `ItemInstance.portion /
  created_minute / age_minutes` (+ `sync_age`, `set_age_rate`,
  `spoil_state`, `absorb_age`); `ItemContainer.spoil_multiplier`
  (`set_spoil_multiplier`); `LootContainer.spoil_multiplier`;
  `FurnitureCatalog` keys `spoil_multiplier`, `interaction`.
- Furniture: `RestFurniture` / `Sink` are StaticBody3D providers on
  layers 1 + 4 built by `HouseBlockout._interactive_piece()`; they talk
  to the actor's "Rest" / "Consume" children (duck-typed).
- `DayNightLighting` (world/): `lighting_at(hour)` pure, `apply()`,
  `sun_energy()`, `lights_on`.
- HUD: `ClockWidget`, `MoodleList` (built in code by hud.gd),
  sleep overlay; `Equipment.is_consumable()` lets food on the hotbar.

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
Round 8: `sound_emitted` is emitted only by SoundManager (categories are
data ids: `footstep_jog`, `window_smash`, …); `shouted(character, ok,
reason)`, `hazard_hurt(character, hazard, region)`.
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
Round 7: `health_drained(character, amount, cause)` (HealthComponent.drain),
`time_advanced(from, to)`, `minute_passed(total_minute)`,
`hour_passed(hour, day)`, `day_passed(day)`, `time_speed_changed(step,
scale)`, `need_level_changed(character, need, level, label)`,
`moodles_changed(character, moodles)`, `item_consumed(character, item)`,
`sleep_started(character, bed)`, `sleep_ended(character, reason)`,
`rest_started(character, seat)`, `rest_ended(character, reason)`.
Round 5: `inventory_changed(owner)`, `container_opened(actor,
container)`, `container_closed(actor, container)`, `item_transferred(from,
to, item)`, `timed_action_started(actor, action, label, seconds)`,
`timed_action_finished(actor, action, completed)`,
`wound_reopened(character, region)`.
Round 9: `barricade_changed(fixture, planks)`, `barricade_plank_broken(fixture,
source)`, `furniture_moved(furniture, door)` (door null = moved back),
`furniture_destroyed(furniture, source)`, `skill_xp_gained(character, skill,
xp)`, `skill_leveled(character, skill, level)`.
Round 10: `game_saved(slot)`, `game_loaded(map)`, `game_notice(text,
seconds)`.

## Physics layers
1 world · 2 player · 3 zombies · 4 interactables · 5 items · 6 occluders ·
7 doors · 8 window_panes · 9 barricades (R9: furniture blocking a door —
taken off layer 1 so the re-baked navmesh ignores it; player mask 453 and
zombie mask 455 include 9; the zombie obstacle ray is 7 + 9). Window planks (≥ 2) add a body on 8.

Vehicles (R8.5): body 1 + 6 (navmesh-baked, fades), trunk / glovebox
containers 4 only.

Generated world (R11): ground + world bounds 1; per-chunk `Solids` body 1
(fences, props, lamp poles, tree trunks, pond walls — baked into that
chunk's navmesh); gas pumps 1 + 4; the gas-station canopy roof 6 only
(an occluder, never solid); crops and canopies have no collision.

Beds / sofas / sinks (R7): 1 + 4 (+6 when tall). World items (`WorldItem`): layer 4, mask 0. Loot containers /
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
`furniture`, `world_config` (R5), `interior_light` (R7, room OmniLights),
`glass_shards`, `noise_rings`, `sound_debug` (R8), `vehicle`, `day_night` (R8.5),
`navigation_mesh_source_group` (the map root; parsed by NavBaker),
`barricade`, `splinters`, `interaction_extension` (R9); planks and blocking
furniture join `breakable` while they block. `saveable`, `pause_menu` (R10).
`world_builder`, `world_chunk`, `world_solids`, `street_lamp`, `gas_pump`,
`world_map_overlay` (R11; street lamps are also `interior_light`).

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
- `tests/perf/perf_zombies.gd` (`scripts/perf.sh`, calm, `--hostile`,
  `--noisy` — 30 random SoundManager events / s emitted from inside the
  measured bracket — and `--horde-noise` — 60 clustered zombies + 10
  window smashes / s; every mode checks avg and p99 (16 ms, horde 20 ms);
  `scripts/perf.sh --noisy|--horde-noise` runs one mode)
  measures the scene-tree part of every physics step with two probe
  nodes at the lowest / highest physics priority (all `_physics_process`
  callbacks incl. move_and_slide; the Jolt step for kinematic bodies is
  negligible). `Performance.TIME_PHYSICS_PROCESS` is unusable for this:
  it refreshes once per second and covers whole catch-up bursts.
- `scripts/test.sh` fails on any `SCRIPT ERROR` and on any plain
  `ERROR:` line except the audio-device and `ERR_CANT_OPEN` ones.
- R10: `tests/integration/test_unstaged_{1337,7,99}.gd` play the brief's
  FINAL ACCEPTANCE TEST unstaged (new game on that world seed, the map's
  own zombies, no item injection / stat forcing, only time advanced) with
  the bot in `acceptance_bot.gd` (navmesh walking with the real
  controller, door opening, PZ tactics: hold behind the smashed window,
  shout to lure, shove-and-hit, aim-walk backwards vs groups, retreat to
  the garage doorway; teleports only when stuck, reported);
  `test_acceptance.gd` is the staged save / load-focused variant (+
  corrupt / busy / static round trips), `test_save_scene.gd` the critic
  fixes (tampering, data ids + reordering, ghost hotbar, infection
  events, autosave rules, menus / confirmations / overlay, new game); `tests/unit/test_save.gd` covers
  every to_dict / from_dict pair, versioning, corrupt JSON and atomic
  writes; `tests/perf/perf_save.gd` (`scripts/perf.sh --save`) times
  save / load with 200 zombies.
- Integration tests of other systems disable the map's zombie spawner
  (`scene.get_node("Zombies").auto_spawn = false`) in `setup()`.
