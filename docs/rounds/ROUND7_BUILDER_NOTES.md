# Round 7 — builder notes (world time, needs, food, sleep / rest)

## Decisions

- **World time is an autoload (`TimeManager`)** counting game minutes
  since 1 July 07:00; calendar maths are the pure `GameClock`. 1 real s =
  1 game min at 1× (`data/world/time_config.tres`). The map's
  `WorldConfig` resets it on load and on free, so tests / reloads never
  inherit a sped-up engine or a late hour.
- **Fast-forward = `Engine.time_scale`** (the PZ way: everything runs
  faster, physics included), not a separate "world rate". It is refused
  while a zombie chases the player and drops back to 1× within 0.25 s
  of a chase starting. Pause = `SceneTree.paused` (TimeManager is
  PROCESS_MODE_ALWAYS and keeps reading keys). Godot 4 scales the
  physics delta (the tick count per real second is unchanged), so 4× =
  4/60 s steps.
- **Needs are simulated in whole game-minute steps** from
  `EventBus.time_advanced`, so they follow every speed, a sleep, or a
  test's `TimeManager.advance(360)` identically. The stats live in
  StatsComponent (saved with it, `stat_changed` for free); the levels
  (with 5-point hysteresis) and effects are owned by `NeedsComponent`
  because StatsComponent thresholds are "low fraction" based.
- **Max stamina has one owner**: `Character.combined_max(base, penalties,
  multipliers)`; injuries set a penalty (`injury`), needs a multiplier
  (`needs`) — they no longer overwrite each other.
- **Spoilage is lazy**: an `ItemInstance` keeps `age_minutes` + a stamp
  and the rate of the container holding it (`ItemContainer
  .spoil_multiplier`, fridge 0.25); the age syncs whenever it is read or
  the item moves. No per-frame cost, fridges work for any container.
- **Portions**: eating takes ONE item out of its stack for the duration
  (busy `eat`); a half portion comes back as a separate `portion 0.5`
  item that never stacks. Interruption (damage, walking off) returns the
  item untouched.
- **Can opening**: `FoodData.requires_tool` / `fallback_tool_tag` are
  item TAGS (tin opener `can_opener`, knife `blade`), searched in the
  storage and the hands; the knife cut is rolled before the busy action
  starts, so it hurts but does not cancel the meal.
- **Sleep**: `Engine.time_scale` 4 (zombies still simulate) + a
  game-time skip to 60 game min per real second (8 h ≈ 8 s). Wakes on
  fatigue 0, damage, a sound within 8 m, a zombie within 8 m / chasing,
  or a 600-real-second cap. Wounds get the skipped game time
  (RestComponent → `InjuryComponent.tick`), and sleeping while bleeding
  is refused. Rest = busy `rest` context (stamina ×3 via the stats
  profile), ended by moving.
- **Furniture interactions** come from the catalog (`interaction: bed /
  seat / sink`): HouseBlockout builds `RestFurniture` / `Sink` bodies
  instead of plain boxes; they talk to the actor's "Rest" / "Consume"
  children (duck-typed). Sinks added to House A's kitchen and bathroom.
- **Lighting**: `DayNightLighting` keyframes keep 07:00-18:30 identical
  to the Round 1-6 look (energy 0.85) so no earlier screenshot changes;
  the night is grey-blue with moonlight 0.12 + ambient 0.5; one warm
  unshadowed OmniLight per room switches on at night (ground spill like
  reference 3).
- The HUD's right edge is a stack: clock (ref 4) → moodles → body panel
  (moved down under the moodles). Loot window area untouched.

## What was built

- core: `time_manager.gd` (autoload), `game_clock.gd`; data/world
  `time_config.gd/.tres`; 6 input actions (F5-F8, `,` `.`).
- survival/: `needs_component.gd`, `needs_math.gd`, `consume_action.gd`,
  `rest_component.gd`, `danger.gd`; data/survival `needs_profile.gd/.tres`.
- interaction/: `rest_furniture.gd`, `sink.gd`; world/
  `day_night_lighting.gd`; ui/hud `clock_widget.gd`, `moodle_list.gd`.
- Items: FoodData (fresh / rotten days, eat seconds, half, tool tags,
  empty item), `ItemData.fill_item_id`, new `water_bottle_empty`;
  ItemInstance portion / age; ItemContainer spoil multiplier (+ saved
  `age` / `portion` keys); stacks need equal spoil state.
- Character: stamina max penalties / multipliers, swing time
  multipliers, `needs` child; StatsComponent regen multipliers;
  InjuryComponent `heal_multiplier`; MeleeCombat applies swing time.
- Player: `Needs`, `Consume`, `Rest` nodes; `use_item` eats,
  `consume_item(item, portion)`; ItemActions `consume` /
  `consume_half` replace the Round-6 stubs; food / drink on the hotbar.
- HouseBlockout: interactive pieces, sink basin detail, room lights,
  fridge `spoil_multiplier`; catalog: bed / sofa / sink entries.
- HUD: clock, moodles, sleep fade, survival notices; inventory condition
  column shows Fresh / Stale / Rotten, partial items "(50%)".

## Tests

- Unit `test_needs.gd` (14): clock / day rollover, calendar + seasons +
  temperature, TimeManager unit signals + save round trip, levels with
  hysteresis, effects mapping, activity rates, spoil state by age,
  fridge vs cabinet ageing (+ transfer, save), consume maths, portion
  weight / stacking, empty bottle data, tool resolution, lighting curve,
  combined max stamina.
- Integration `test_survival_scene.gd` (21): 6 h → Hungry + Thirsty +
  moodles + clock + max stamina; jogging thirst ×1.5; beans refused
  without opener (menu + notice); knife opens (busy bar label, forced
  cut path, −30 hunger); eat half; drink → empty bottle → Fill bottle +
  Drink at the kitchen sink through the real interaction; zombie hit
  interrupts eating (item back); hotbar key eats; starving −1 HP / min;
  regen fed vs very hungry; rotten bread → Nauseous + drain; fridge vs
  cabinet milk; sleep refused "Not tired" / "danger nearby" / bleeding;
  sleep advances ≈ 4.8 h, fatigue 0, engine back to 1×, notice; sleep
  heals wounds; noise within 8 m wakes, far noise doesn't, a hit wakes;
  rest on the sofa ×3 stamina, moving gets up; fast-forward refused while
  chased + auto-drop; F8 / F5 keys (4× = 1 game min per 15 frames,
  pause freezes time); lighting 23:00 vs 12:00 + house lights.
- Updated R6 tests: Use on food eats; no Eat entry without a
  ConsumeAction; FoodData `fresh_days`.
- Screenshots `23_moodles_clock`, `25_eating`, `24_night` (+ F7 / F6
  through the input map).

## Numbers

After the critic fixes: `scripts/test.sh` 288 tests, 0 failed (≈ 490 s). Before:
`scripts/test.sh`: 271 tests, 0 failed (≈ 458 s). `scripts/perf.sh`:
calm 2.8 ms, hostile 6.2 ms (budgets 8 / 10; Round-6 code on the same box
6.1 ms hostile — one earlier run read 13 ms while another Godot process
was running). `scripts/screenshots.sh`: OK twice (25 shots).

## Critic fixes

1. Health drains emit `EventBus.health_drained(character, amount, cause)`
   (not character_damaged, so nothing is interrupted); a needs drain
   wakes the sleeper ("Woken: dying of thirst"); sleep is refused when
   hunger / thirst would reach the critical level during the expected
   sleep ("Too thirsty to sleep"), or while bleeding.
2. `Character.busy_cancelled(context)` + `cancel_busy()` replace four
   copies of kill-tween / end_busy; override, cancel and death all emit
   it and eat / bandage / search / sleep / rest restore their state.
3. Item ages are elapsed minutes; `TimeManager.epoch` (bumped on reset /
   load) makes items re-stamp — load order does not matter.
4. Lazily rolled perishables are aged (world age + time played) × the
   container's spoil rate.
5. Fill bottle "No room for the water"; eating refused "Paused"; HUD
   state label shows the busy verb; death resets speed to 1×.
6. Needs: hunger 2.5 / 1.2 asleep, thirst 3.5 / 1.8 asleep, thresholds
   hunger 15/25/50/80, thirst 25/55/88, starving −6 HP/h, dying of
   thirst −10 HP/h → no water ≈ 37 h. Loud warning + moodle pulse at the
   second-worst level.
7. Hunger = kcal / 25 (data updated to match). House A already feeds
   ≈ 3.2 days on average (30 seeds: min 1.35, max 5.8) — tables kept.
8. `WorldConfig.water_shutoff_day` = 14 → "The water is off".
9. Sleep: Engine ×8 + 20 game min / real s (8 h = 24 s, 192 s of zombie
   simulation; tick count unchanged → perf unchanged). Wake radius for
   zombies 10 m. Test: a zombie 31 m away investigating the front door
   reaches it during the sleep and wakes the player.
10. Night: neutral dark-grey ambient, moon 0.1, per-room shadowed
   SpotLights aimed at the floor (no bleed through walls), warm emissive
   window panes at night; bigger clock speed pips.

Screenshot runner: one of five post-fix runs lost the Round-4 fight
(random knockdowns → cascade); the runner now seeds the combat and
injury RNGs (deterministic evidence) and checks the clock against the
TimeManager instead of a fixed hour. perf: calm 2.5 ms, hostile 5.8 ms.

## Gotchas

- Godot 4 `Engine.time_scale` scales the `_physics_process` delta, not
  the tick count: 15 physics frames at 4× = 1 game minute.
- An `InputEventAction` (the screenshot runner's `_press`) is not an
  `InputEventKey`: TimeManager must match actions on any event type.
- Needs keep running during every integration test (1 game min / s):
  harmless (tests last minutes, levels need hours) but tests that set
  exact values should expect the few minutes of drift.
