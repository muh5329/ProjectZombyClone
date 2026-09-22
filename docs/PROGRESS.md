# Progress Log

One entry per gauntlet round, newest first. Scores are the verifier rubric
(0–10). "Critic" refers to the independent reviewer pass (a separate agent
that did not write the code).

---

## Round 3 — Basic zombie AI, senses, navigation, health (2026-09-22)

### Goal
Zombies that are readable and dangerous: state machine, vision/hearing/
proximity senses, navmesh pathing through door openings, door banging,
attacks that damage a new HealthComponent; player death and restart.

### What changed
- `ZombieProfile` resource (all tuning: speeds 0.9/1.6, vision 14 m/120°,
  memory 8 s, attack 0.9 m / 0.5 s windup / 1.5 s cooldown / 12 dmg,
  health 60, AI/sense/repath cadences, door damage 8, hold distance…).
- `Zombie` (CharacterBody3D, layer 3) + `ZombieVisual`, `ZombieCorpse`
  (layer 4, "Search corpse" placeholder), `ZombieSenses` (staggered 6 Hz
  vision with LOS on layers 1+7+8, hearing with wall attenuation,
  proximity with LOS), `ZombieAI` on a generic RefCounted `StateMachine`:
  Idle/Wander/Investigate/Search/Chase/Attack/AttackDoor/LostTarget/
  Stunned/Dead. Max 4 attackers per target, others hold at 1.4 m.
- Navigation: `NavBaker` bakes a NavigationMesh at load from layer-1
  static colliders; door leaves moved to layer 7, window panes to layer 8
  so doorways bake as passable and open windows are see-through.
- Doors: 300 hp, `take_damage`, broken state (leaf gone, always open,
  still targetable), `door_banged` + 10 m sound. Breakable contract
  (group + `take_damage`/`blocks_path`) so AI never imports Door.
- Sound stub: `EventBus.sound_emitted(position, radius, intensity,
  category, source)`; footsteps (sneak 2 / walk 4 / jog 8 / sprint 14 m),
  doors 6 m, window smash 18 m, bangs 10 m.
- `HealthComponent` on Character; player death → busy, overlay, R restart.
- HUD: ♥ health bar, "! N chasing", red damage vignette (shader).
- `ZombieSpawner` (seeded, ≥15 m from player, outside buildings).
- Perf script: 200 zombies calm 4.2 ms, all hostile 8.4 ms avg (budgets
  8 / 10 ms) on the 2-core CI box; far calm zombies use cheap navmesh
  sliding out of the physics space.

### Files changed
zombies/**, ai/state_machine/*, data/zombies/*, characters/{health_component,
footstep_emitter,body_helpers,character}.gd, world/{nav_baker,world_query}.gd,
interaction/{door,window,wall_fixture}.gd, core/event_bus.gd, ui/hud/*,
maps/test_ground.tscn, project.godot (layers 7/8, Jolt, restart action),
tests/unit/test_{state_machine,zombie_senses,health}.gd,
tests/integration/test_zombie_scene.gd, tests/perf/perf_zombies.gd,
scripts/{perf,test}.sh, docs/*.

### Tests performed
`scripts/test.sh` → **112 tests, 0 failed** (54 unit, 58 integration);
runner now also fails on plain `ERROR:` lines. `scripts/screenshots.sh` OK
(11_zombies_overview, 12_chase, 13_damage_flash). `scripts/perf.sh` OK.
Critic probe: 18 adversarial cases.

### Bugs discovered (critic) → all fixed
Corpse left outside the physics space (die() ordering) → untargetable,
order-dependent test; bites through walls (no LOS on attack/proximity);
broken door untargetable; stale "N chasing"; zombies blind through open
windows; freed sound source crashed a listener (engine ERROR not caught by
runner); non-deterministic AI phase from instance ids; take_damage(0) ok;
door query allocations per tick; hostile perf 18 ms → 8.4 ms; hardcoded
tuning outside profile; zombie.gd god object; AI importing Door/Building;
duplicated movement math; vacuous dead-player test; health/stamina bars
same colour.

### Failed approaches
- Baking doors on layer 1 sealed doorways in the navmesh → layer 7.
- Reading Performance monitors per frame (1 Hz refresh) gave flat perf
  numbers → per-step timing with priority-bracket nodes.
- Instance-id stagger looked random but broke seeded repeatability.

### Verifier score (after fixes; critic pre-fix in brackets)
Functionality 8 (6) · System Integration 8 (7) · Survival Depth 6 (4) ·
Architecture 7 (6) · Performance 7 (5) · UX/Feedback 7 (6) ·
Bug Resistance 7 (4).

### Highest-priority remaining issue
The player cannot fight back or shove; zombies are only avoidable.
Round 4 (melee, push, body-region injuries) is next.

---

## Round 2 — Interaction framework, enterable house, dimetric camera + cutaway (2026-09-22)

### Goal
One enterable house with doors and windows, a universal interaction
framework (objects provide their own actions), and the Project-Zomboid
look: orthographic dimetric camera with roof hiding / wall cutaway indoors.

### What changed
- Camera now orthographic, 30° elevation, 45° yaw steps, zoom as view size
  (10/14/20/28). Perspective path kept behind `orthographic=false`.
- `Interactable` component API + `PlayerInteraction` (sphere query on layer
  4, facing-weighted, line-of-sight ray, E / 1-4). Refusals surface via
  `interaction_refused` → HUD notice ("Locked", "Blocked", "Busy").
- `WallFixture` base → `Door` (swing with collision, blocked check against
  bodies, 0.5 s cooldown, locked flag) and `HouseWindow` (open/close/
  smash/climb; climb is actor-owned busy tween, costs stamina −12/s,
  `hazard` flag for smashed glass).
- `BuildingPlan` resource → `HouseBlockout` generates floor, split wall
  segments, lintels, doors, windows, rooms, roof. `validate()` warns on bad
  plans. House A (10×8, 4 rooms, 2 ext + 3 int doors, 7 windows).
- `OcclusionManager`: inside → roof hidden, eye-facing exterior walls and
  current-room interior walls become 0.35 m stubs; outside → occluders on
  the eye→player ray fade (per-instance material). Room hysteresis
  (0.35 m exit margin), per-building caches, 10 Hz.
- HUD: interaction prompt, "Inside: room — building", refusal notices.

### Files changed
camera/{isometric_camera,occlusion_manager}.gd, interaction/{interactable,
wall_fixture,door,window}.gd, buildings/{building,room,building_plan,
house_blockout}.gd, data/buildings/house_a.tres, player/{player.tscn,
player_interaction.gd}, characters/character.gd,
data/characters/{character_stats_profile.gd,player_stats.tres},
core/event_bus.gd, ui/hud/*, maps/test_ground.tscn, project.godot,
world/blockout_box.gd, tests/unit/test_{room,house_plan,door_window}.gd,
tests/integration/test_house_scene.gd, tests/screenshot_run.gd, docs/*.

### Systems added
Interaction, Doors/Windows, Buildings/Rooms, Occlusion/cutaway, busy state.

### Tests performed
`scripts/test.sh` → **81 tests, 0 failed** (42 unit, 39 integration).
`scripts/screenshots.sh` → OK; new shots 07_door_prompt, 08_inside_cutaway,
09_window_open, 10_after_climb. Critic probe: 19 adversarial cases.

### Bugs discovered (critic) → all fixed
Permanent player freeze if a window is freed mid-climb; interaction through
walls (no LOS); `orthographic` toggle broke zoom; room-boundary thrash
(11 flips in 12 steps); stamina regen while climbing; doors swinging
through bodies; instant door spam; no plan validation; door/window code
duplication; hardcoded heights; per-tick String allocation; shared-material
fading; HUD hard-coded child lookup; a vacuous door test.

### Failed approaches
- Area3D overlap for interactables never reported static bodies → direct
  shape query. - `MeshInstance3D.transparency` is a no-op in GL
  Compatibility → per-instance material_override duplicate.
- First interior-wall cut rule cut partitions in every room → restricted to
  the current room.

### Verifier score (after fixes; critic pre-fix in brackets)
Functionality 8 (7) · System Integration 8 (7) · Survival Depth 5 (4) ·
Architecture 7 (6) · Performance 7 (6) · UX/Feedback 7 (5) ·
Bug Resistance 7 (5).

### Highest-priority remaining issue
Nothing threatens the player yet. Round 3 zombies (states, senses,
navigation through doors) are the gate for combat, sound and barricades.

### Recommended next action
Round 3: zombie base + AI state machine (Idle/Wander/Investigate/Chase/
Attack/Search/LostTarget/Stunned/Dead), vision cone + hearing hook,
NavigationRegion3D baked from the blockout, 8-12 zombies on the test map,
attack that deals damage to a new HealthComponent (full injuries in R4).

---

## Round 1 — Player + isometric camera (2026-09-22)

### Goal
Bootstrap the Godot 4.6 project and deliver a responsive, *vulnerable-human*
locomotion controller with an elevated isometric camera, on a blockout test
map, with a headless test harness and screenshot evidence pipeline.

### What changed
- New project (`gl_compatibility` renderer, input map, physics layers,
  autoloads `EventBus` + `GameManager`).
- `Character` base (CharacterBody3D) integrating `MovementComponent` (pure
  velocity model: sneak/walk/jog/sprint, accel/decel, multiplicative speed
  modifiers keyed by source) and `StatsComponent` (named stats, per-context
  rates, hysteresis threshold states, save-ready dict I/O).
- Stamina economy from a data resource (`data/characters/player_stats.tres`
  → `CharacterStatsProfile`): sprint −18/s, jog −1.5/s, walk/sneak +1/s,
  idle +3.5/s; exhausted at ≤2 %, exits at ≥40 %; ×0.6 speed while
  exhausted; 4 s minimum "winded" lockout. Effort scaling: stamina cost is
  proportional to speed actually achieved (pinned against a wall ≈ free,
  30 % stick ≈ 30 % cost).
- `PlayerController`: camera-relative WASD → intent; `scripted` mode for
  tests. Player registers in `_enter_tree` so re-parenting is safe.
- `IsometricCamera`: pivot/arm rig, 8 yaw headings (Q/R), 4 zoom levels
  (wheel/±), smooth follow, guards for empty zoom list / zero yaw step /
  freed target.
- HUD (event-driven via EventBus): mode label, stamina bar+% with low /
  exhausted colouring and flash, "Too winded to sprint" and "Exhausted!"
  notices, F3 debug overlay, key hints.
- Blockout test map with 1 m grid shader, wall, crates, car, trees.
- Test harness: `tests/test_runner.gd` (+ watchdog, load-failure detection),
  `scripts/test.sh` (fails on any SCRIPT ERROR), `tests/screenshot_run.gd`
  driving the game through **real input events** under Xvfb.

### Files changed
project.godot, icon.svg, .gitignore, core/{event_bus,game_manager}.gd,
characters/{character,movement_component,stats_component}.gd,
data/characters/{character_stats_profile.gd,player_stats.tres},
player/{player.gd,player.tscn,player_controller.gd},
camera/isometric_camera.gd, world/blockout_box.gd,
assets/materials/grid_ground.gdshader, maps/test_ground.tscn,
ui/hud/{hud.gd,hud.tscn}, tests/{test_runner,test_case,screenshot_run}.gd,
tests/unit/test_{movement,stats,controller}.gd,
tests/integration/test_player_scene.gd, scripts/{test,screenshots}.sh,
docs/*.

### Systems added
Movement, Stamina (first stat), Camera, HUD, EventBus, test harness.

### Tests performed
- `scripts/test.sh` → **39 tests, 0 failed** (17 unit, 22 integration
  running the real scene with real physics). Report: `tests/output/report.txt`.
- `scripts/screenshots.sh` → **SCREENSHOT_RUN: OK** (exercises the input
  map: jog, rotate camera ×2 + verify camera-relative direction changed,
  zoom, sprint to exhaustion, sneak).
- Critic pass wrote 13 probe cases (edge cases, rapid toggling, bad config).

### Screenshots / evidence
`tests/output/01_spawn.png … 06_sneak.png`, `contact_sheet.png`.
Exhausted shot shows speed 2.04 m/s (= 3.4 × 0.6), red bar, "(EXHAUSTED)"
and the denied-sprint notice.

### Bugs discovered (critic + own testing)
1. `is_equal_approx` in `StatsComponent.set_value` swallowed sub-epsilon
   changes → slow drains would never accumulate.
2. Empty `zoom_levels` → index −1 every frame.
3. Player registered in `_ready` but unregistered in `_exit_tree` →
   re-parenting left `GameManager.player == null`.
4. Camera accessed `target.global_position` after target left the tree.
5. Sprint drain keyed on intent ≠ 0 → 5 % stick or sprinting into a wall
   paid full price.
6. `yaw_step_degrees = 0` → division by zero; `rotation.y` unbounded.
7. Two sources of truth for exhaustion (Character flag vs stat state).
8. `StatsComponent.tick()` was dead code duplicated by Character regen.
9. HUD polled Character internals despite the EventBus.
10. Camera tests relied on wall-clock (flaky on faster machines).
11. Runner silently skipped scripts with parse errors and did not fail on
    SCRIPT ERROR (comment claimed otherwise).
12. Screenshot runner waited on render frames → physics catch-up distorted
    timings under software rendering.
13. Input.action_press() doesn't reach `_unhandled_input`.
14. Hand-typed non-orthonormal light transform blew out lighting.

### Bugs fixed
All 14 above. Exhaustion is now owned by `StatsComponent` thresholds with
enter/exit hysteresis; `Character` reacts to the `threshold` signal.
Regen/drain live in the stats profile as per-context rates and are applied
by `StatsComponent.tick(delta, context, effort)`.

### Failed approaches
- Static typing against gameplay classes inside a `-s` SceneTree script:
  compiles before autoloads → "EventBus not found". Use untyped refs there.
- Wall-clock `Time.get_ticks_msec()` for the winded timer: diverges from
  physics time at low fps. Replaced with a physics-time countdown.

### Verifier score (after fixes; critic's pre-fix score in brackets)
| Criterion | Score |
|---|---|
| Functionality | 8 (7) — all Round-1 capabilities work via the real input map; edge cases covered |
| System Integration | 7 (5) — EventBus actually used (HUD, sprint denial); stat state is the single source of truth |
| Survival Depth | 5 (3) — sprint is a real decision (5.6 s burst, ~11 s idle to recover, jogging costs); only one need exists yet |
| Architecture | 7 (6) — components pure/testable, tuning in a Resource; HUD still polls for debug + winded-clear |
| Performance | 8 (8) — trivial load; no per-frame string work outside debug overlay |
| UX / Feedback | 6 (5) — mode, stamina, low/exhausted, denied sprint all legible; no world-space cue, facing indicator weak |
| Bug Resistance | 7 (4) — 39 tests incl. edge probes; runner fails on script errors; watchdog |

### Highest-priority remaining issue
No world to be vulnerable *in*: no building, no occlusion handling, no
interactables. Round 2 (enterable house, doors, windows, roof/wall fading)
is the gate for everything after it.

### Recommended next action
Round 2: interaction framework (`Interactable` with object-provided
actions), one house with rooms, doors (open/close), windows (open/close/
smash/climb), camera occlusion fading, and the "vault/climb through window"
movement. Keep blockout visuals.
