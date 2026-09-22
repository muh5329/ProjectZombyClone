# Round 2 — builder notes (for the integrator / critic)

## What was built

- **Camera** (`camera/isometric_camera.gd`): orthographic dimetric rig by
  default (`orthographic`, `pitch_degrees = 30`, `zoom_levels` = view sizes
  10/14/20/28, `orthographic_distance = 45`), perspective path kept with
  `perspective_zoom_levels`. New helpers `view_direction_flat()` and
  `eye_position_for()` so the occlusion code does not care about the
  projection. Group `isometric_camera`. `directional_shadow_max_distance`
  in the map raised to 120 because the ortho camera sits 45 m back.
- **Interaction** (`interaction/interactable.gd`,
  `player/player_interaction.gd`): component + provider-callback API,
  sphere query on layer 4, E / 1-4 input (`action_1..4` added to
  `project.godot`), EventBus signals `interaction_target_changed`,
  `interaction_performed`. `Character.is_busy` / `set_busy()` added.
- **Door / HouseWindow** (`interaction/door.gd`, `interaction/window.gd`).
- **Buildings** (`buildings/building_plan.gd`, `room.gd`, `building.gd`,
  `house_blockout.gd`, `data/buildings/house_a.tres`), placed at
  (−14, 0, −10) in `maps/test_ground.tscn` under `Buildings/HouseA`.
- **Occlusion** (`camera/occlusion_manager.gd`) as `OcclusionManager` node
  in the map; `BlockoutBox` props now also on layer 6 + group `occluder`.
- **HUD**: `PromptLabel` (bottom centre) and `RoomLabel`; `format_prompt()`
  is static and unit-testable.
- **EventBus**: 7 new signals (see ARCHITECTURE).
- **Docs**: SYSTEMS, ARCHITECTURE, KNOWN_ISSUES updated.

## Tests

`scripts/test.sh`: 71 tests, 0 failed, no SCRIPT ERROR (~75 s).
- Unit (new): `test_room.gd` (3), `test_house_plan.gd` (7),
  `test_door_window.gd` (9).
- Integration (new): `test_house_scene.gd` (12): generation, closed door
  blocks → E opens → walk in, close again blocks, cutaway (roof hidden,
  S/E walls stub with collision untouched, N/W full, restore on exit),
  no-thrash, outside fade, interior door → room change, open-window climb
  (busy flag, intent ignored, lands outside), smashed climb sets hazard +
  event, open window still blocks walking, number-key alternatives and
  disabled-action refusal, HUD prompt / room line.
- Existing camera zoom test now checks `camera.size` in ortho mode; added
  `test_camera_pitch_and_perspective_fallback`.

`scripts/screenshots.sh`: `SCREENSHOT_RUN: OK`. New shots:
`07_door_prompt`, `08_inside_cutaway`, `09_window_open`, `10_after_climb`.
The run rotates back to 45° / default zoom before the house section; the
exhaustion sprint now goes left (A) because right ran into the house.

## Failed approaches / gotchas

- `Area3D` on the player did not report overlaps with the static Door /
  Window bodies (empty `get_overlapping_bodies()` after 20+ physics
  frames, headless and windowed). Switched to
  `PhysicsDirectSpaceState3D.intersect_shape` — simpler and deterministic.
- `class_name Window` is illegal (engine class). Now `HouseWindow`.
- W+D in the screenshot run was "north" only at yaw 45°; the earlier
  camera rotations left it at 135°, so the player walked along the wall.
- First interior-wall rule cut every eye-facing partition in the building;
  restricting it to walls bounding the current room reads much better
  (compare ref 4).
- Wall albedo 0.78 was blown out under the sun + filmic tonemap; lowered
  to ~0.62.

## Not finished / left for later

- Cutaway is per-facade, not per-ray (see KNOWN_ISSUES 1-2).
- Door swing does not check for a blocking character.
- Climb landing is not validated against props.
- No tool / strength requirement for Smash, no glass injury (R4).
- `Interactable` prompt position is not yet used for a world-space marker;
  the HUD shows a screen-space prompt only.
- PROGRESS.md round entry intentionally not written (integrator).

## Critic pass (fixes applied)

1. Climb tween owned by the actor (`Character.begin_busy/end_busy/busy_tween`);
   window emits `window_climbed` only if still valid. Test: window freed
   mid-climb → lock clears, player lands.
2. LOS ray (layer 1) in `PlayerInteraction`; test: window behind a 0.2 m wall
   not targetable.
3. `IsometricCamera.orthographic` setter re-applies projection + zoom list;
   runtime toggle test.
4. Room hysteresis in `Building.locate` (exit margin 0.35 m, enter-deep rule);
   ±6 cm shuffle test fires ≤ 2 changes.
5. Busy stats context (`&"climb"`, `stamina_rate_climb = -12`); test.
6. Door blocked check (leaf box at target angle vs layers 2+3) → "Blocked";
   tests for zombie in the arc and player in the doorway.
7. 0.5 s toggle cooldown on all wall fixtures → "Busy".
8. `BuildingPlan.validate()` + warnings; unit tests (bad plan, house_a clean).
9. `WallFixture` base class extracted; Door / HouseWindow extend it.
10. Heights moved into `BuildingPlan` (door_height, window_sill/top),
    `CharacterStatsProfile.eye_height`, exported tolerances on Room /
    OcclusionManager.
11. Structural action-list comparison (no per-tick String building).
12. Per-building wall/roof cache (pruned, invalidated on exit /
    tree_exiting), reused ray query.
13. Duck typing for busy actors; HUD reads actions from the signal payload.
14. Per-instance fading via `material_override` duplicate.
    `MeshInstance3D.transparency` was tried first and is a no-op in GL
    Compatibility (player invisible behind faded walls) — reverted to the
    override approach; no material cache, shared materials untouched.
15. `interaction_refused` signal; HUD notice shows the reason; prompt greyed
    when nothing is enabled and hidden while busy.
16. Door test drives 120 frames from the same start before/after opening;
    stub test walks into the stubbed wall. Prop "Wall" colour toned down.

Tests: 81 (unit 42, integration 39), 0 failed, no SCRIPT ERROR.
