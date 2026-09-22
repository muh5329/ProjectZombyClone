# Round 3 — builder notes (basic zombie AI)

## What was built

- **Data**: `data/zombies/zombie_profile.gd` (`ZombieProfile`) +
  `zombie_basic.tres` — speeds (0.9 / 1.6), turn, vision 14 m / 120°, eye
  1.5 m, hearing ×1, proximity 1.5 m, memory 8 s, attack 0.9 m / 0.5 s /
  1.5 s / 12 dmg, door damage 20, health 60, head ×3, stagger 20, stun
  0.8 s, wander 10 m, idle 2–8 s, search 4–6 s.
- **Generic FSM**: `ai/state_machine/state_machine.gd`, `state.gd`
  (RefCounted, pure, weak back-reference).
- **Zombie**: `zombies/zombie.gd` + `zombie.tscn` (CharacterBody3D, layer
  3, mask 1+2+3+7, capsule 1.7, shared 3-surface mesh, `Movement`, `Stats`,
  `Senses`, `AI`, `NavigationAgent3D`), `zombie_senses.gd`,
  `zombie_ai.gd`, ten states under `zombies/states/`, `zombie_spawner.gd`.
- **Navigation**: `world/nav_baker.gd` (`NavBaker extends
  NavigationRegion3D`) in `maps/test_ground.tscn`; layer 7 "doors"
  (`Door` leaf no longer on layer 1); player mask 1+3+7; project nav cell
  defaults 0.15 / 0.1.
- **Doors**: `health` 120, `take_damage()`, `broken` state, sounds.
  Windows: sounds. `EventBus.sound_emitted` + `FootstepEmitter` on the
  player (1 Hz, 2/4/8/14 m).
- **Health**: `characters/health_component.gd`, `Character.health` /
  `take_damage()` / death → busy; `CharacterStatsProfile.health_max`;
  `restart` input action (R).
- **HUD**: health bar, "!  N chasing", damage vignette shader
  (`ui/hud/damage_vignette.gdshader`), death overlay + restart.
- **EventBus**: `character_damaged`, `character_died`, `sound_emitted`,
  `zombie_state_changed`, `zombie_spotted_target`, `zombie_lost_target`,
  `zombie_attacked`, `zombie_died`; `door_state_changed` gains `broken`.
- **Physics engine**: Jolt.
- **Perf**: `tests/perf/perf_zombies.gd`, `scripts/perf.sh`.
- **Docs**: SYSTEMS, ARCHITECTURE, KNOWN_ISSUES, README (perf.sh).

## Tests

`scripts/test.sh`: **112 tests, 0 failed, no SCRIPT ERROR, no ERROR lines**
(~165 s after the critic pass;
Round 2 had 81 in ~90 s — each integration test now also bakes the
navmesh, ~0.2 s, and the zombie tests wait on real AI timers).

- Unit (new, 12): `test_state_machine.gd` (4: enter/exit/signals/history,
  update-driven transitions + time, transient chaining bounded, owner +
  force re-enter), `test_zombie_senses.gd` (5: cone/range, cone edges
  59°/61°, LOS + degenerate inputs, mode multipliers, profile loads with
  the expected numbers), `test_health.gd` (3: damage/death events on both
  buses, invulnerable/heal/revive, door damage → broken with events and
  sound radii). `test_door_window.gd` contract test updated (door layers
  7+4+6, window 1+4+6).
- Integration (new, 13, `test_zombie_scene.gd`): navmesh covers ground +
  house interior + doorway and paths into the bedroom; idle → wander moves
  at shamble speed near home; player in cone → chase < 1 s (+ event, red
  head, HUD "!  1 chasing", chase speed); behind a wall → not spotted
  (`occluded`) then spotted in the open; sneaking at 10 m → not spotted,
  jogging → spotted; window smash at ~9 m → investigate (yellow head) →
  reaches within 2 m of the window → search; proximity → attack → damage
  = 12 after ≥ 20 frames windup, one `zombie_attacked(hit=true)`, flash
  strength > 0, bar 88, no second hit during cooldown, second hit later;
  target vanishes → chase on memory ≥ 7.5 s → `lost_target` → search →
  wander, HUD cleared; footstep inside → investigate → attack_door →
  health drops → broken → zombie inside → chases; `take_damage(999)` →
  dead, layer 4 / mask 0, event with killer, collapsed, "Search corpse
  (No inventory yet)", player targets and walks over the corpse; head hit
  ×3 stuns, light hit does not; spawner: 10 on the navmesh, outside
  buildings, ≥ 15 m, seeded, and a second spawner with the same seed picks
  the same points; player death → overlay, "Dead", no movement, zombies
  ignore the corpse.
- Existing house/player integration tests set `auto_spawn = false`.

`scripts/screenshots.sh`: `SCREENSHOT_RUN: OK`. New: `11_zombies_overview`
(zoomed out, a jittered group of 7 + the map's 10), `12_chase` (red-head
zombie closing on the player, "!  1 chasing"), `13_damage_flash` (bite:
red vignette, Health 88%). The run checks the map spawned 10, the chase
starts within 1.5 s, the HUD shows "!", the bite lands within 8 s and the
flash is visible.

`scripts/perf.sh`: 200 zombies, 600 physics frames, loud noise so ~180
of them move: **≈ 6–7 ms avg physics step** (median ≈ 6.5, p90 ≈ 12) on
the 2-core dev box where the empty scene costs ≈ 1.3 ms; budget 8 ms.
Quiet variant (`PERF_MODE=quiet`) ≈ 7 ms (100+ wandering).

## Failed approaches / gotchas

- `NavigationMesh` default source mode parses only the region's
  children → 0 polygons. Switched to
  `SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN` with the map root in the group.
- Door leaves on layer 1 were baked → interior unreachable. Layer 7.
- Recast rounds agent radius to cell units: 0.35 → 0.5 with cell 0.25
  closed the 0.9 m doorways. Cell 0.15 / radius 0.3 / height 1.5 (the
  lintel gap is only 2.1 m minus voxel slop). Navmesh vertices sit
  0.2 m above the floor; all path code ignores Y.
- Map queries right after `bake_finished` return zeros; wait for
  `map_get_iteration_id` to change.
- `@onready` of the parent is not ready when children `_ready`; explicit
  `setup()`.
- Chase used the live target position while the 6 Hz `visible_target`
  was stale → a teleported player "leaked" its new position (test caught
  it). Snapshot from the senses instead.
- `wait_until` counts process frames, which run far faster than physics
  headless → gameplay waits timed out early. `wait_physics_until`.
- Perf: first numbers (17 ms) were mostly a measurement artefact —
  `TIME_PHYSICS_PROCESS` is per main-loop iteration and the post-spawn
  catch-up burst reports 50 ms for dozens of "frames". After fixing the
  probe the real cost was ≈ 9 ms: ≈ 3 ms GDScript (≈ 12 µs per moving
  zombie per tick on this box), the rest engine transform/physics sync.
  Steps that helped: one `_physics_process` per zombie, AI at 20/10 Hz,
  settled zombies skip movement, inlined velocity step with cached
  speeds, cheap movers out of the physics space at 30 Hz, one mesh per
  zombie, Jolt. What did not help measurably: lowering AI Hz alone,
  merging visuals alone (each < 0.5 ms).
- `StateMachine` ↔ state cycle leaked at exit (RefCounted); WeakRef.
- The pre-existing screenshot section runs with the 10 seeded zombies
  live; seed 1337 works, but one of them reaches and bites the player
  near the west window (harmless, "1 chasing" already shows on shot 10).

## Critic pass (fixes applied)

1. `die()` ordering / cheap-movement setter guard → death now creates a
   separate `ZombieCorpse` (StaticBody3D, layer 4) and frees the zombie;
   the setter no longer looks at `dead`. `last_target_distance == INF`
   means "unknown" and never goes cheap.
2. No biting through walls: chest-to-chest ray (1+7+8) to enter Attack,
   at every swing, and for proximity detection. Test
   `test_no_bite_through_a_wall`.
3. Broken doors keep a layer-4 body → "Close door (Door is broken)"
   reachable; test `test_broken_door_prompt_reachable`.
4. HUD chase count pruned on `tree_exiting` (connected per chaser), in
   `chasing_count()` and every frame; test
   `test_stale_chase_count_is_pruned_when_zombie_freed`.
5. Window glass is a child body on layer 8 `window_panes` (closed only);
   sill + header stay layer 1; player/zombie masks + vision/interaction
   rays include 8. Test `test_vision_through_open_window_but_not_closed`.
6. `scripts/test.sh` fails on plain `ERROR:` lines (ALSA/audio and
   ERR_CANT_OPEN whitelisted). `sound_emitted` listener takes a Variant
   source and guards validity.
7. Tick phases (AI counter, sense accumulator, cheap-move counter, re-path
   offset) derive from the seeded `ai_seed`; test
   `test_same_seed_gives_same_state_sequence` (two spawners, seed 99,
   3 zombies, identical state histories after 9 s).
8. `Zombie.take_damage(<= 0)` → {ok:false}; interaction LOS mask 1+7+8;
   a hit zombie without a target turns toward the source and investigates.
9. Perf: re-path staggered from the seed; senses drop to 0.5 s while the
   target is in sight and the zombie is hostile; attack slots (max 4) —
   surplus zombies hold at 1.4 m or once stuck in the crowd, re-trying
   every 1.5 s; query objects created once. `perf_zombies.gd --hostile`
   forces all 200 into Chase on an invulnerable player and re-forces
   every second; `scripts/perf.sh` runs both and exits 1 over budget
   (8 ms calm / 10 ms hostile). Measured: calm ≈ 5.1 ms, hostile ≈ 8.3 ms.
10. `Door._blocked_at` reuses one query + shape.
11. Zombie uses `MovementComponent.compute_velocity()`; shared helpers in
    `characters/body_helpers.gd` (Character delegates too).
12. `ZombieAI` imports no Door/Building: breakable contract (group
    `breakable`, `take_damage`, `blocks_path`) + `world/world_query.gd`.
13. All tuning in `ZombieProfile` (cheap distance, AI/sense/repath rates,
    slacks, timeouts, stuck times, search constants, hold, lunge…).
14. `zombie.gd` split: `zombie_visual.gd` (mesh, tint, lunge, flash,
    collapse; assets on a tree-owned `ZombieAssets` node — statics holding
    Resources are reported as leaks at exit) and `zombie_corpse.gd`.
15. Door health 300, zombie door damage 8 (≈ 75 s alone, ≈ 20 s for
    four); `door_banged(door, source)` + 10 m sound per bang; hearing
    halved through a wall / closed door (one ray, `hearing_wall_attenuation`).
16. Attack tell: the visual lunges 0.25 m forward during the windup and
    the head flashes white at the swing (visible in `13_damage_flash`).
18. "♥ Health" dark-red bar with white text above stamina; exhausted
    stamina is orange-red.
19. Player-death test spawns the zombie face to face inside proximity
    range. Tests: 112 total (unit 54, integration 58), 0 failed.

## Not finished / left for later

- No zombie animation / attack swing visual; head tint is the readability
  device.
- Cheap-mode bodies are outside the physics space (see KNOWN_ISSUES 0).
- Zombies only attack doors that are on their path ahead; no side hits,
  no window climbing, no shoving.
- Hearing has no occlusion; Round 8.
- Only the player is prey.
- `PROGRESS.md` entry intentionally not written (integrator). Nothing
  committed.
