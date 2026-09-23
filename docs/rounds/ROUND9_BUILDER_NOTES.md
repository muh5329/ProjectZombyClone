# Round 9 — builder notes (barricading doors and windows)

## Decisions

- **Barricade = data + a component created on demand.** `BarricadeData`
  (wood_planks.tres) holds every number; `BarricadeComponent` is a child
  "Barricade" of the Door / HouseWindow, created by the first plank, so
  the 12 fixtures of House A pay nothing until used. Door / HouseWindow
  only append `BarricadeComponent.actions_for()` and route the two ids
  to `perform()`; the rules live in one place.
- **Planks are the breakable, not the fixture.** Fixtures answer
  `breakable_target()` (planks while any, else themselves); the zombie AI
  resolves a ray hit through `resolve_breakable()` (breakable_target →
  group → breakable child) — still no Door / Window types in the AI. The
  outermost (last) plank takes each hit, no overflow: 4 planks really are
  4 layers. `door.take_damage()` / `window.take_damage()` also route to
  the planks so older callers keep working.
- **Materials only on completion.** `TimedWork` (new, shared by nailing,
  prying, disassembling and pushing) runs the actor's busy tween,
  cancels on `character_damaged` / `busy_cancelled`, and calls
  `on_done` only when the time elapsed; the nail step re-checks the
  hammer / plank / nails then (dropped meanwhile → refused). The
  hammer goes into the hands for the job (PZ-like; also shows it).
- **Side = actor side** (PZ): the first plank decides; from the other
  side you can neither add nor remove ("Barricaded on the other side").
  Boards sit on that face, stacked 1.2 cm outward each so tilted boards
  never z-fight, with a seeded ±8° tilt.
- **Boards are wider than the brief's 0.1 m** (0.2 m × opening + 0.32 m ×
  4 cm, dark nail heads, a grain line, a crack mesh below half health):
  0.1 m boards were illegible at the default zoom; the 31 shot reads
  like ref 2's boarded windows. Colour darkens with health
  (`color_for`).
- **Sight**: a `PlanksBody` (inner class) on the window-pane layer 8
  appears from `vision_block_planks` (2) planks — zombie vision, bites
  and melee lines all use 1+7+8 already, so nothing else changed. Its
  `sound_obstacle_kind()` is OPEN: the ×0.8/plank factor is applied once
  per fixture by `SoundManager.obstacle_attenuation` (`seen` list; the
  opening paths pass `skip_fixture` and multiply `o.factor` instead —
  no double counting).
- **Zombies enter through windows via NavigationLink3D**, not rays:
  each exterior window owns a bidirectional link (±0.75 m) whose
  `enter_cost` is open/smashed 1, closed 10, +8 per plank. The AI looks
  at its current path (`path_types` / `path_owner_ids`) at re-path ticks
  or when stuck on the sill (≤ 4 Hz): a link owned by a window, our end
  within 0.9 m, goal across → bang while `blocks_path()` (planks, then a
  closed pane: 2 hits smash it) → `climb_window` (1.6 s scripted move in
  `Zombie._step_climb`, collision mask 0). A ray-based "window ahead"
  was rejected: paths never aim at windows without links, and grazing
  rays would make zombies bang on windows they walk past.
- **Doors cannot carry a nav cost** (doorways are baked walkable), so
  "prefer the weakest entry" is decided at the barricade:
  `consider_detour()` scores the building's other exterior openings
  (distance + 8 m/plank + 2 for a closed window, ≤ 14 m) and walks to one
  ≥ 4 m better; reaching a detour window takes it directly (the navmesh
  alone would lead back to the free doorway).
- **Attacker slots on the obstacle** (`claim_attacker`, max 3, weakrefs,
  pruned on death / free); surplus zombies wait in attack_door facing it
  without hitting. Doors without planks keep the Round-3 unlimited rule.
- **Furniture: snap, not drag.** `FurnitureWork` (an Interactable
  *extension*: a child in group `interaction_extension` whose actions are
  appended by the body's Interactable — containers / sofas stay
  unaware). "Block door with X" snaps the piece flush behind the nearest
  closed door (3.5 m; 2 m reached nothing in House A), adds layer 9 +
  group breakable; the door refuses "Blocked by furniture". Zombies break
  the door, then their obstacle ray (now 7 + 9) finds the piece.
- **Explicit actions.** "Remove barricade" must never be E: actions may
  carry `explicit: true` (kept by `normalise_action`); `interact()` and
  the HUD's E marker skip them. Barricaded windows hide "Smash window" so
  every entry keeps a number key (4 max).
- **Carpentry is small but real**: `SkillComponent` (XP table, levels
  0-10, −5 %/level time, +5 %/level plank health, to/from dict, EventBus
  signals, HUD "Carpentry 1 ↑").

## What was built

- data: `data/barricades/wood_planks.tres`; 5 sound categories
  (hammering 18, wood_break 10, barricade_bang 12, furniture_scrape 6,
  sawing 10); catalog keys `movable` / `block_health` / `disassemble`;
  planks in the garage tool crate; zombie profile `window_climb_seconds`,
  `window_link_distance`, `detour_margin`, `detour_search_radius`,
  `detour_seconds`; physics layer 9 "barricades".
- code: `buildings/barricade_data.gd`, `interaction/barricade_component.gd`,
  `interaction/furniture_work.gd`, `interaction/timed_work.gd`,
  `inventory/carried_items.gd`, `skills/skill_component.gd`,
  `effects/splinters.gd`, `zombies/states/zombie_state_climb_window.gd`;
  changes in WallFixture / Door / HouseWindow / Interactable /
  PlayerInteraction / ZombieAI / chase / investigate / attack_door /
  Zombie / ZombieVisual / SoundManager / OcclusionManager / HUD /
  CharacterAnimator + 2 clips (`hammer`, `push`) / HouseBlockout /
  Player scene ("Skills").
- tests: `tests/unit/test_barricade.gd` (10), `tests/integration/
  test_barricade_scene.gd` (13); updated action-list expectations in
  test_door_window / test_house_scene. Screenshots 31-33
  (`SCREENSHOT_ONLY=r9` runs only that section while iterating).

## Numbers

- 1 zombie vs 2×24 hp planks with a 0.5 s cooldown: ~6 bangs; 3 zombies
  finish in < 0.6× the time (test). Default rhythm (1.9 s per bang, 8
  damage): one zombie needs ~15 s per fresh plank, ~60 s for a full
  window; three ~20 s.
- Perf (200 zombies): calm unchanged; hostile 7.6-7.9 ms avg, p99 12-13
  ms (one 17.7 ms outlier in 4 runs → the stuck-path link check was
  throttled to 4 Hz); noisy 4.0 / 7.2; horde 1.4 / 4.0.

## Failed approaches / gotchas

- `screenshot_run.gd` referenced `BarricadeComponent` statically →
  it compiled before the autoloads and every call failed ("Nonexistent
  function in base GDScript"). Loaded at run time instead.
- `bool(actor.get("is_busy"))` on a plain Node3D test actor is
  `bool(null)` → script error; `TimedWork.is_busy()` checks the property.
- Planks added to an OPEN door (screenshot setup) swung with the leaf and
  sent zombies out of range → `add_plank` now honours
  `barricade_block_reason` too.
- The "Wall" prop at z = 2 hides the house front from a zombie south of
  it: vision tests stand the zombie at z = 1.

## Critic fixes (same round)

1. Nailing adds the plank first and only then consumes materials / gives
   XP; a door / window changing state under the job cancels it.
2. `TimedWork` is the one cancel path (damage, walking off, Esc / E /
   action key via `PlayerInteraction.cancel_work`, override / death);
   `ConsumeAction` now runs on it (its own damage / move handling is gone).
3. Crowds: slotless zombies queue at 1.6 m and take freed slots, re-ask
   for a better entry every 3-5 s (seeded); stuck zombies look 3 m ahead
   for the barricade. `world/entry_planner.gd` scores entries for both the
   window links and the detours, with a per-building opening cache.
   10 zombies vs one weak window: 3 attackers at once, 240 vs 480 frames.
4. Block door: same room + clear line + a free spot (world, furniture,
   characters). 5. No plank while a body is in the window. 6. Unsearched
   containers roll their loot before breaking apart. 7. `from_dict` before
   `_ready`. 8. Box of nails → "Open box" (50); loose nails 3-12, box 10 %.
9. The 14 m reading was the meter decaying between hammer blows (hold
   0.8 s < 1.5 s period): it now holds for the category's duration.
10. Blocking furniture leaves layer 1 for layer 9 (like a door leaf) and
   every move re-bakes the navmesh: the old spot becomes walkable, the
   doorway stays a path so zombies still meet (and smash) the piece.
