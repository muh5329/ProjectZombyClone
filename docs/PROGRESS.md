# Progress Log

One entry per gauntlet round, newest first. Scores are the verifier rubric
(0–10). "Critic" refers to the independent reviewer pass (a separate agent
that did not write the code).

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
