# Vertical-Slice Review (after Round 10)

Independent reviewer pass, 2026-09-23, on commit `e706507` (Round 10).
Required by `docs/BRIEF.md`: *"After Round 10: STOP. Perform a complete
vertical-slice review before expanding."* No source files were changed by
this review. A throwaway probe test was written under `tests/integration/`,
run, and deleted.

## 0. What was run (this session, 2-core box)

| Command | Result |
|---|---|
| `scripts/test.sh unit` | **184 tests, 0 failed** (6.6 s) |
| `scripts/test.sh integration-a` | **49, 0 failed** (327 s), includes `test_unstaged_99` |
| `scripts/test.sh integration-b` | **32, 0 failed** (261 s), includes `test_acceptance`, `test_unstaged_7` |
| `scripts/test.sh integration-c` | **70, 0 failed** (321 s), includes `test_unstaged_1337` |
| `scripts/test.sh integration-d` | **82, 0 failed** (355 s) |
| `scripts/screenshots.sh` | `SCREENSHOT_RUN: OK`, 37 PNGs refreshed in `tests/output/` |
| `scripts/perf.sh` | **OK**: 200 zombies calm 4.64 ms avg / 8.63 p99, hostile 8.34 / 14.47, noisy 4.38 / 8.49, horde-noise (60) 1.52 / 4.20; save 5.4 ms, load 375 ms (145 ms of it navmesh bake); 3000 dropped items save 55 ms / load 657 ms |
| `test_unstaged_acceptance_seed_1337` rerun ×3 | **3/3 pass** (148, 152, 161 s) |
| Hotbar probe (throwaway) | Confirmed the root cause of the hotbar ghost bug (§6, item 4) |

Total: **417 tests, 0 failed.** No SCRIPT ERROR or engine ERROR lines.

---

## 1. First Playable Target: the 18 verbs

Every verb works in the real scene with real input or the real player
verbs. The container the brief puts them in, "ONE small playable
neighborhood", does not exist yet (§3).

| # | Brief item | Verdict | Evidence |
|---|---|---|---|
| 1 | Walk and sprint | **PASS** | `test_sprint_is_faster_and_drains_stamina`, `test_exhaustion_blocks_sprint_and_recovers`, `test_walk_mode_speed_and_recovery`; shots 02, 05 |
| 2 | Enter buildings | **PASS** | `test_closed_door_blocks_then_opens_and_lets_player_in`, `test_inside_cutaway_hides_roof_and_cuts_camera_facing_walls`; shot 08 |
| 3 | Open doors | **PASS** | `test_open_door_can_be_closed_and_blocks_again`, `test_door_refused_when_swing_arc_is_blocked`; shot 07 |
| 4 | Break / open windows | **PASS** | `test_open_window_climb_out_lands_outside`, `test_smashed_window_climb_sets_hazard`, `test_glass_hazard_scratches_feet_and_remove_glass_clears_it`; shots 09, 10 |
| 5 | Search containers | **PASS** | `test_open_kitchen_cabinet_rummages_then_shows_items`, `test_reopen_keeps_the_same_items`, `test_trunk_and_glovebox_searchable`; shot 19 |
| 6 | Pick up items | **PASS** | `test_pickup_and_cycle_weapons`, `test_drop_item_and_pick_it_up_again`, `test_bag_on_the_ground_opens_like_a_container` |
| 7 | Equip a melee weapon | **PASS** | `test_pickup_into_inventory_and_x_cycles`, `test_hotbar_assign_and_real_key_press_equips`, `test_weapon_on_hand_bone_and_swing_clips`; shot 21 |
| 8 | Fight zombies | **PASS** | `test_bat_swing_hits_zombie_in_front`, `test_multi_target_bat_vs_knife`, `test_shove_cancels_windup_and_pushes_back`, `test_knockdown_down_multiplier_and_get_up`; shots 14–16 |
| 9 | Take damage | **PASS** | `test_attack_damages_player_after_windup`, `test_zombie_attack_inflicts_region_injury_and_infection`, `test_balance_bot_three_zombies_is_deadly`; shots 13, 17 |
| 10 | Become hungry and thirsty | **PASS** | `test_eight_hours_make_hungry_and_thirsty_with_moodles`, `test_jogging_makes_you_thirsty_faster`; shot 23 |
| 11 | Eat and drink | **PASS** | `test_beans_with_a_knife_open_and_fill_you_up`, `test_drink_water_leaves_empty_bottle_and_refill_at_sink`, `test_eat_half_leaves_a_half_item`; shot 25 |
| 12 | Carry inventory with weight limits | **PASS** (UX caveat) | `test_heavy_load_slows_real_movement`, `test_overloaded_refuses_sprint_and_drains_stamina_faster`, `test_capacity_refusal_greys_rows`; shot 22. Caveat: the HUD shows "Carrying 6.9 / 8 kg" (the encumbrance threshold) while the inventory header shows "Space 4.70 / 20 kg" (capacity). Two different denominators confuse (shot 21). |
| 13 | Kill zombies | **PASS** | `test_zombie_death_leaves_interactable_corpse`, `test_head_hit_multiplier_and_stun`; 2 kills in every unstaged run |
| 14 | Loot zombie corpses | **PASS** | `test_search_corpse_after_killing_a_zombie`, `test_corpse_ids_unique_across_spawners_on_one_seed`; shot 20 |
| 15 | Barricade a door or window | **PASS** | `test_barricade_window_from_outside_consumes_materials_and_blocks_climbing`, `test_zombie_breaks_planks_one_by_one_then_climbs_in`, `test_furniture_blocking_the_door_must_be_destroyed_by_zombies`; shots 31–33 |
| 16 | Sleep or rest | **PASS** | `test_sleep_advances_time_and_reduces_fatigue`, `test_sleep_interrupted_by_zombie_noise`, `test_rest_on_sofa_regenerates_stamina_faster` |
| 17 | Save the game | **PASS** | `test_final_acceptance_playthrough`, `test_pause_menu_named_slots_overwrite_and_delete_confirmations`, `test_saving_is_refused_while_busy`; shot 34 |
| 18 | Reload and see the same world state | **PASS** (minor caveats) | `test_doors_windows_vehicles_and_zombie_states_round_trip`, `test_tampered_save_is_refused_before_anything_changes`; screenshot run: mean pixel diff 0.0027 between before-save and after-load. Caveats: chase / attack / stunned zombie states come back as "investigate"; the hotbar looks different after load (§6, item 4). |
| — | **"ONE small playable neighborhood"** (8–12 houses, store, warehouse, gas station, roads, forest, 30–50 zombies) | **FAIL** | `maps/test_ground.tscn`: 1 house + 1 one-room garage, 1 straight road, 2 box trees, 10 zombies (§3) |

**Score: 18/18 verbs pass. The neighborhood the verbs belong to fails.**

---

## 2. Final Acceptance Test in natural play

The unstaged tests (`tests/integration/test_unstaged_{1337,7,99}.gd` driving
`acceptance_bot.gd`) start a real new game with the map's own zombies. They
inject no items and force no stats. The only shortcut is advancing game time
(`TimeManager.advance`) to make the survivor hungry, thirsty and tired, which
matches the fast-forward a player would use.

### Pass rate this session

| Run | Seed | Result | Wall time | Kills | Swings | Glass climbs for a wound | Final HP |
|---|---|---|---|---|---|---|---|
| suite (a) | 99 | PASS | 217 s | 2 | 7 | 1 | 96 |
| suite (b) | 7 | PASS | 163 s | 2 | 4 | 2 | 94 |
| suite (c) | 1337 | PASS | 160 s | 2 | 8 | 1 | 96 |
| rerun 1 | 1337 | PASS | 148 s | 2 | 5 | 0 | 96 |
| rerun 2 | 1337 | PASS | 152 s | 2 | 7 | 0 | 100 |
| rerun 3 | 1337 | PASS | 161 s | 2 | 7 | 4 | 94 |

**6/6 passes overall; seed 1337 passed 4/4.** Combat randomness is real: the
swing count ranges from 4 to 8 and the glass climbs from 0 to 4. None of it
changed the outcome. The bot had no teleports in any run. Four runs are too
few to promise more than about 75 % reliability at 95 % confidence, but no
failure showed up.

### Per step

| Brief step | Status | Notes |
|---|---|---|
| Spawn in a house | PASS | Inside House A with a spare t-shirt |
| Search the kitchen / find food | PASS | Kitchen cabinets. `HouseA/kitchen/2` (the fridge) is logged as "not targeted" on every seed, a small reachability or LOS issue with the fridge from the bot's spot. |
| Equip a backpack | PASS | Fixed placement on the bed, not rolled loot |
| Find a weapon | PASS | Fixed bat in the living room |
| **Hear zombies outside** | **PARTIAL** | The test checks the reverse: a zombie hears the player's smash. **The game has no audio at all** (no `AudioStreamPlayer` anywhere) and shows no cue for zombie moans, banging or footsteps. The HUD's only zombie signal is "! N chasing". A player cannot hear zombies outside. |
| Open or climb through a window | PASS | Smash + climb |
| Explore another building | PASS (thin) | The "other building" is the one-room garage shed |
| Fight or evade zombies | PASS | See the balance note below |
| Hungry, thirsty → eat, drink | PASS | Eats food from the bag, drinks at the kitchen sink |
| Become injured → treat it | PASS | The wound came from **window glass in every run**, never from a bite. Bandage or torn t-shirt rags. |
| Carry supplies home | PASS | Hammer from the garage workbench |
| Barricade the safehouse | PASS (partial) | 2–3 planks on the smashed window. Scarcity stopped the rest ("Need planks", "Need 2 nails"), which is good design. On seed 99 **the front door was broken down while the bot was away** and the bot still slept. The test accepts "closed **or broken**". |
| Sleep | PASS | |
| Save / Exit / Reload | PASS | Reloads into a fresh scene (`SaveManager.load_game`). "Exit" to the process is covered by the menu tests, not by this bot. |
| Confirm player, inventory, killed zombies, looted containers, barricades, world time | PASS | Every field is checked by `acceptance_bot.gd` step 16 |

**Balance finding:** in all 6 runs the survivor finished the fight at
**100 HP**. Every fight is held at the smashed living-room window. Zombies
climb in single file (1.6 s, unable to bite), so one kills them safely with
4–8 swings. Only 2 of the 10 zombies ever engage. 8 are still alive at the
save. The window chokepoint makes combat close to risk-free. That is the
opposite of the brief's "even small groups of zombies should remain
dangerous" (the open-field balance tests do show 3 zombies kill the bot).

**Final Acceptance Test verdict: PASS, with one PARTIAL** ("hear zombies
outside": no audio or audible-threat cue).

---

## 3. Map scope vs the brief (largest gap)

| Brief (first playable neighborhood) | Current `maps/test_ground.tscn` | Gap |
|---|---|---|
| 8–12 houses | **1** (`data/buildings/house_a.tres`, 10×8 m, 4 rooms) | −7 to −11 |
| 1 convenience store | **0** (the `convenience_store_shelf` loot table exists but only unit tests use it) | missing |
| 1 warehouse | **0** | missing |
| 1 gas station | **0** (no fuel items) | missing |
| several roads | **1** straight road strip across a 200×200 m grass plane | no network, sidewalks or intersections |
| forest perimeter | **2** box "trees" | missing |
| 30–50 zombies | **10** (`ZombieSpawner count = 10`, 2 near House A) | −20 to −40 |
| (extra) | 1-room garage (`shed_a.tres`), 7 parked vehicles, 1 wall, 3 crates | |

What already exists for the scale-up:

- `BuildingPlan` is data: rooms, walls, openings, furniture, explicit save ids.
- `HouseBlockout` generates buildings from a plan.
- Loot tables resolve by building × room × container.
- The spawner is seeded.
- Save ids come from plan data.

What will hurt:

1. **Building placement is hand-written in the `.tscn`.** There is no map or
   neighborhood layout resource.
2. **Plans are single-storey rectangles.** Commercial interiors (store aisles,
   warehouse racks, a gas-station forecourt with pumps) have no furniture
   types yet.
3. **The whole map shares one navmesh.** A bake takes about 145 ms today, and
   every furniture move rebakes the whole map (KNOWN_ISSUES R9).
4. **Each room has one shadowed spotlight** (KNOWN_ISSUES R7). Twelve houses
   would mean about 60 shadowed lights.
5. **`acceptance_bot.gd` and many integration tests use absolute House A
   coordinates** (for example `Vector3(-7, 0, -2.85)`). The neighborhood must
   keep House A and the garage where they are, or rewrite the bot.
6. **Perf is measured headless only.** Rendering cost for 30–50 animated
   zombies, 12 buildings and their lights has never been measured.
   `perf_zombies` spawns 200 zombies on today's map, which has 279 navmesh
   polygons.

---

## 4. The six critic lenses

### Gameplay critic: **5 / 10**

**Strengths**

- The loop is complete and survivable in natural play.
- Stamina, encumbrance and noise are real decisions:
  - sprinting lasts 5.6 s;
  - hammering carries 18 m;
  - smashing a window draws zombies.
- Scarcity is felt: the bot runs out of nails or planks after 2–3 planks.
- Sleep is refused when zombies are near, when you are bleeding, or when
  thirst would turn critical.
- There are several solutions: sneak, shout-lure, shove, chokepoints, furniture
  blocking, planks.

**Weaknesses**

- With one house and one shed there is nothing to decide about where to go.
  Nothing makes a supply run a story.
- The window chokepoint trivialises combat: every natural run ends at
  94–100 HP, and all damage came from glass.
- 8 of the 10 zombies never matter.
- There is no audio, so tension depends only on sight.
- Food on the map lasts days (`test_balance_house_a_food_lasts_days`), so
  there is no push to leave.

### Systems critic: **7.5 / 10**

**Strengths**

- These systems genuinely interlock:
  - sound → hearing → moan relays → door banging;
  - barricades → sight and sound muffling → `EntryPlanner` detours;
  - needs → sleep → wake-on-danger;
  - injuries → pain → movement and swing strength;
  - glass → foot cuts;
  - encumbrance → stamina drain;
  - spoilage → fridge;
  - water shut-off on day 14;
  - all of it saved.

**Weaknesses**

- Crafting is only "tear clothing" and "take furniture apart". There is no
  recipe system.
- Temperature is display only. There is no weather, wetness, electricity or
  generator.
- Vehicles are parked props.
- Clothing is cosmetic.
- There is no population sim. Zombies are under-simulated during sleep
  (Engine ×8 gives 192 s of zombie time for 8 game hours).
- Injury timers run on physics seconds, not game minutes.

### Architecture critic: **8 / 10**

**Strengths**

- `Character` + components with intent input.
- The `EventBus` is the only link between systems.
- Objects offer their own actions (`Interactable.get_actions` / `perform`).
- Content is data: items, weapons, loot tables, buildings, barricades, sound
  categories, outfits, vehicles.
- `TimedWork` is the single cancel path for timed jobs.
- `Saveable` contract, two-phase schema-validated load, and a load allow-list
  (no arbitrary `load()` from save paths).
- 417 tests with sharding.

**Weaknesses**

- `ui/hud/hud.gd` (940 lines), `zombie_ai.gd` (766) and `loot_window.gd` (761)
  are heading toward god objects.
- Map composition lives in the `.tscn`, not in data.
- `WorldState` is redundant with the `saveable` group.
- Hardcoded map coordinates in the tests make changing the map expensive.
- `crafting/`, `simulation/`, `weather/` and `world_chunk` do not exist yet.
  That is expected at this phase, but no seam for chunked save records exists
  yet (the save is one file per map).

### Performance critic: **7 / 10**

**Strengths**

- 200 zombies: 4.6 ms avg calm and 8.3 ms hostile (p99 14.5 ms) per physics
  step on 2 cores.
- Cheap-mode far zombies, staggered senses, spatial-hash hearing, animation
  LOD.
- Save 5 ms, load 0.4 s. 3000 dropped items stay within budget.

**Weaknesses**

- The hostile p99 (14.5 ms) is close to its 16 ms budget.
- Rendering has never been measured on a GPU. The Xvfb screenshots run at
  4–8 fps in software, which says nothing either way.
- Nothing has been tested at neighborhood scale:
  - many buildings;
  - thousands of world objects;
  - many loot containers;
  - navmesh bake time with 12+ buildings;
  - the whole-map rebake on every furniture move;
  - dozens of shadowed interior lights.
- The brief's "simulation outside the player's immediate area" does not
  exist.

### UI/UX critic: **6.5 / 10**

**Strengths**

- The HUD covers every item on the brief's list:
  - health, stamina (with "max N %" cap), pain;
  - per-region injuries with BLEEDING / bandaged;
  - weapon condition bar;
  - hunger, thirst and fatigue moodles;
  - noise meter with LOUD, "! N chasing";
  - E prompt with 4–7 alternative actions and refusal reasons ("Need 2
    nails", "No empty bottles").
- The loot and inventory windows follow ref4.
- Save / load menus have confirmations.

**Weaknesses**

- **No audio at all.**
- The action prompt overlaps the key-hint panel (shots 21, 23:
  "[6] Disassemble" is drawn over "WASD move").
- Two weight numbers disagree (8 kg threshold vs 20 kg capacity).
- Moodles are coloured letters.
- The loot window is fixed at 1280×720.
- Hotbar ghost icons (§6, item 4).
- There is no zombie-awareness cue for anything outside the screen.
- The key-hint panel is permanent.

### "Project Zomboid-like experience" critic: **5.5 / 10**

| Quality | Score | Notes |
|---|---|---|
| Dangerous exploration | 3 | Only one other building (a shed). There is nowhere dangerous to explore. |
| Scarcity | 7 | Loot retuned for scarcity. Nails and planks cap barricades. Water shuts off on day 14. Food in one house lasts days. |
| Persistent consequences | 8 | Kills, corpses, loot, planks, broken doors, glass, dropped items and blood all persist through save/load. |
| Detailed inventory | 8 | Weight and capacity, bags, hotbar, split/drag, condition, spoilage, containers. No wearable clothing. |
| Vulnerability | 6 | Three zombies kill you in the open. Bites infect. Exhaustion. But chokepoints are risk-free (§2). |
| Environmental interaction | 7 | Doors, windows, smash, climb, glass, sinks, beds, sofa, furniture push/block/disassemble, car trunks. |
| Base fortification | 7 | Planks with HP, zombies breaking through, furniture blocking, carpentry XP. Only wood. |
| Zombie pressure | 4 | 10 zombies, no migration or population, no hordes from sound across cells. Pressure falls to nothing once 2 are killed. |
| Preparation before expeditions | 3 | There is no expedition worth preparing for. Pack weight matters, but the only trip is 20 m. |
| Long-term progression | 3 | Carpentry is the only skill. No farming, generator, vehicles or crafting. The water shut-off is the only long-term clock. |

---

## 5. Visual comparison with `docs/reference/ref1..4`

Closest match first:

1. **ref4, interior cutaway + loot UI: good match.**
   - Matches: the dimetric camera; the roof hidden and camera-facing walls cut
     when inside (shot 08); the two-column loot / inventory window with
     name / type / qty / kg / cond and Loot All / Transfer All (shot 19); the
     hotbar at the bottom centre; the clock top right.
   - Missing: textured walls and floors (flat colours now); prop and loot
     clutter on the floor; the vertical icon toolbar on the left; wall
     decals.
2. **ref1, fortified base by daylight: partial.**
   - Matches: the palette and camera angle; the people and zombie silhouettes
     (shot 28) read as PZ-like; plank barricades on windows and doors
     (shots 31, 36); the fire pickup and police car props; blood splats.
   - Missing: fences and palisades, parking lots and kerbs, lamp posts,
     multi-storey brick buildings, corpses scattered across the open (corpses
     exist but are few).
3. **ref2, town street with a horde: weak.**
   - Matches: a lined road with parked vehicles (shot 29); zombies crowding a
     building (shot 32).
   - Missing: intersections, sidewalks, shopfronts with signs, lamp posts,
     bins, power lines, yards and fences, a horde of 100+ on screen, fire.
     This gap is the same as the map gap.
4. **ref3, night + snow + light pools: weakest.**
   - Matches: night darkening and emissive window glow (shot 24); police light
     pools (shot 30).
   - Missing: streetlights and pools of warm light, porch lights, weather or
     snow, bare trees, a fenced suburb grid, many houses at night.

---

## 6. Top 10 next actions (smallest coherent rounds, in order)

1. **Round N1: neighborhood layout as data (houses).**
   - Add a `NeighborhoodPlan` / map-layout resource: building-plan
     references + transforms + lot rects + road segments. A builder node
     instantiates it.
   - Add 4–5 house `BuildingPlan` variants (different room layouts,
     1–2 bedrooms, garage variant) placed as 8–12 lots along a small road
     grid (2 streets + a crossing, sidewalks).
   - **Keep House A and the garage at their current coordinates** so
     `acceptance_bot.gd` and the tests still hold.
   - Explicit save ids per lot. Tests: layout validation, ids unique,
     `test_house_scene`-style generation per plan.
2. **Round N2: commercial buildings.**
   - Convenience store (aisles / shelves / counter / cooler, using the
     existing `convenience_store_shelf` table), warehouse (racks, crates,
     large doors), gas station (kiosk + pumps as interactables; fuel can
     item; loot tables).
   - New furniture types in `furniture_catalog.tres`. Loot balance per
     building type.
3. **Round N3: forest perimeter + 30–50 zombies + perf at scale.**
   - Tree / undergrowth scatter (MultiMesh visuals, simple colliders) around
     the edge.
   - Per-zone spawn densities (street, yards, store interior) for 30–50
     zombies.
   - A **rendered** perf probe (GPU, not headless) with the full neighborhood.
   - Navmesh bake time at scale.
   - Per-building or tiled nav regions so furniture moves stop rebaking the
     map.
   - A light budget / distance culling for room spotlights.
4. **Fix the hotbar ghost bug (small; can ride with N1).**
   - Symptom: in `tests/output/36_before_save.png` slots 1 and 3 are dimmed
     "Kitchen Knife" / "Baseball Bat". In `36_after_load.png` they are empty.
   - Root cause, confirmed by a throwaway probe: `Hotbar` keeps a reference
     to an `ItemInstance` after that item stops existing anywhere.
     - A fully eaten candy bar stays on the bar as a dimmed "Candy Bar",
       with `carried: false` and an inventory count of 0.
     - Knife / bat removed by `ItemContainer.clear()` stay as ghosts.
   - On save, `Equipment.to_dict` writes `null` for stack 0 and an
     unresolvable uid otherwise, so after load the slot is empty. The
     after-load state is the correct one; the pre-save ghost is the bug.
   - Fix: clear hotbar references when an item is consumed or destroyed
     (a destroyed flag or stack→0 signal on `ItemInstance`, or validate in
     `hotbar_summary` against `WorldSnapshot`). Keep real ghosts: items
     dropped or stored in the world.
   - The screenshot check `_carried_hotbar` only compares carried slots,
     which is why it missed this. Compare the full summary.
5. **Audio + threat awareness (fixes the acceptance "hear zombies" PARTIAL).**
   - `AudioStreamPlayer3D` feedback driven by the existing `SoundManager`
     events: zombie moans, banging, footsteps, glass, hammering.
   - Plus a directional off-screen cue for loud zombie sounds.
   - No new gameplay rules are needed.
6. **Acceptance bot v2 on the neighborhood.**
   - "Explore another building" should mean the convenience store across the
     road with its zombies, carrying supplies home over open ground.
   - Fail the sleep step when the safehouse door is broken or open.
   - Add a nightly 10-seed sweep and record the pass rate in PROGRESS.md.
7. **Combat pressure pass.**
   - Break the risk-free window chokepoint: zombies grabbing through an open
     or smashed window frame, climbers not strictly single file, a
     pull-through attack.
   - Retune so the natural-play bot actually takes bite damage sometimes.
   - Keep the open-field balance tests.
8. **UX pass.**
   - Stop the prompt overlapping the hint panel (make hints toggleable).
   - Show one weight readout (capacity + encumbrance band).
   - Make the loot window resolution-independent.
   - Moodle icons.
9. **Save fidelity.**
   - Keep chase / attack / stunned zombie states and AI rngs.
   - Move toward per-lot / per-chunk save records (needed once the
     neighborhood is in and before streaming).
   - Remove the redundant `WorldState`.
10. **Doc hygiene.**
    - README says "13 shots" (there are 37) and "417 tests".
    - `KNOWN_ISSUES.md` has broken numbering ("000000000.").
    - Add this review's findings to KNOWN_ISSUES: no audio, chokepoint
      balance, the fridge "not targeted" in the bot, broken front door
      accepted as a safehouse.

Actions 1–3 are the gate. The brief says *"Do not expand the world until
this loop works reliably"*. The loop is now reliable (6/6), and building the
neighborhood is not expanding the world: it **is** the First Playable Target.
Later phases (crafting, weather, vehicles, streaming) should wait until
N1–N3 plus actions 4–6 pass.

---

## 7. Overall verdict

- **Core loop / Final Acceptance Test: PASS.** 6/6 unstaged natural-play runs
  across 3 seeds this session, 417/417 tests, perf within budget. One step
  is PARTIAL: "hear zombies outside", because the game has no audio or
  audible-threat cue.
- **First Playable Target: FAIL on scope.** All 18 verbs pass. But the brief
  defines the target as one neighborhood with 8–12 houses, a store, a
  warehouse, a gas station, roads, forest and 30–50 zombies. The build has
  1 house, 1 shed, 1 road, 2 trees and 10 zombies.

By the brief's rule ("if any critical part fails, the vertical slice does not
pass"), **the vertical slice does NOT yet pass**. The systems and the save
loop are solid, so this is not a rework. What is missing is content at the
right scale, plus proof that performance and balance hold at that scale.
Next: rounds N1–N3 (the neighborhood), with the hotbar ghost fix and audio
cues alongside, then rerun this review.

| Lens | Score |
|---|---|
| Gameplay | 5 |
| Systems | 7.5 |
| Architecture | 8 |
| Performance | 7 |
| UI / UX | 6.5 |
| Project Zomboid-like | 5.5 |
