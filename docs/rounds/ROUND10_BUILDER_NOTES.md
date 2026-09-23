# Round 10 — builder notes (saving and restoring the micro-world)

## What was built

- `core/save_manager.gd` — autoload **SaveManager**: `save_game(slot, map)`,
  `load_game(slot, map)` / `load_data(data, map)` (coroutines), slots,
  refusal reasons, F9 / F10, autosave (wake + every 30 real minutes, only
  for the running game), `new_game`, `quit_to_menu`, `find_saveable`.
- `core/save_file.gd` — **SaveFile**: paths / slots, deterministic JSON,
  `VERSION = 1` + `migrations` hook, `validate`, `decode`, atomic
  `write_atomic` (tmp → rename, `.old` kept until the swap, read falls
  back to it), `list_slots`, `delete_slot`, `first_difference`.
- `core/saveable.gd` — **Saveable**: the contract (group `saveable`,
  `persist_id`, `save_state` / `load_state`, optional `remove_for_load` /
  `saveable_since`) + JSON helpers.
- `world/world_snapshot.gd` — **WorldSnapshot**: `capture(map)`,
  `apply_static` (before the navmesh bake), `apply_dynamic` (synchronous).
- Records on the objects themselves: Player, Zombie, ZombieSpawner,
  ZombieCorpse (+ `ZombieVisual.seed_override / collapse_now`), Door,
  HouseWindow (barricades inside), FurnitureWork, LootContainer,
  HealthComponent, Injury / InjuryComponent (full timers), BloodDecals,
  IsometricCamera. Stable ids for generated doors / windows / furniture
  (`<building>/door|window|furniture/<n>`, build order).
- UI: `ui/menus/pause_menu.gd` (Esc; in the map), `ui/menus/main_menu.tscn`
  (new main scene), `MenuStyle`; HUD `game_notice` / `game_loaded`;
  EventBus `game_saved`, `game_loaded`, `game_notice`; input actions
  `quick_save` (F9), `quick_load` (F10).
- Tests: `tests/unit/test_save.gd` (16), `tests/integration/test_acceptance.gd`
  (4: the playthrough, corrupt save, busy save, static-state round trip),
  screenshot run round 10 (34 / 35 / 36 + a before-save shot and a HUD
  value comparison), `tests/perf/perf_save.gd` in `scripts/perf.sh`.

## Decisions

- **Reload, then apply.** A load never patches the running world: the
  saved map scene is instanced fresh (spawners off, NavBaker not baking),
  the old one is removed (WorldConfig._exit_tree resets TimeManager; the
  SoundManager is cleared / pruned), static state goes in by id, THEN
  the navmesh bakes (moved / destroyed furniture bakes correctly without
  a re-bake), then dynamic state + the player in one synchronous step.
  So `capture()` right after a load returns the loaded data — the
  acceptance test saves again in the same frame and compares.
- **Validate before touching anything.** Read + parse + migrate +
  validate happen first; any failure returns `{ok: false, error}`, emits
  a HUD notice and leaves the game alone. The menus do not await the
  load (they are replaced by it): they pre-check with `read_slot` and
  hand the decoded data to `load_data`.
- **Static vs dynamic.** Map / building objects with deterministic ids
  are `saveable` and restored in place; a static object missing from a
  save was destroyed (`remove_for_load`: furniture taken apart or
  smashed — its dropped contents are saved as world items). Everything
  that can appear / disappear at run time (dropped items, zombies,
  corpses) is a spawn record; the map's own starting items and any
  hand-placed zombies are cleared on load, so a picked-up bat does not
  reappear and a killed zombie never respawns (the spawner is off; the
  spawn counter + rng state are saved so new ids stay unique).
- **Unsearched containers stay unrolled** — only `searched` + contents
  are saved; the lazy roll is seeded by world seed + id, so opening an
  unsearched container after a load rolls exactly what it would have.
- **Safe zombie states** — calm states survive, hostile ones become
  "investigate the last known position"; a climbing zombie is saved at
  its landing point. Corpses keep their look (seed), yaw, pose and
  pockets.
- **Refuse, don't cancel.** Saving while busy is refused rather than
  cancelling the action (an item being eaten / a dressing being applied
  is outside every container; cancelling on F9 would change the game).
- **Deterministic text, semantic identity.** Keys are sorted, records
  sorted by id, the timestamp lives in meta.json only, positions / yaws
  are saved from the exact stored values (item `rotation.y`, corpse
  `yaw`), not derived from bases. Godot's JSON number parser is not
  correctly rounded (measured: ~24 % of random doubles change their
  last bit on a full-precision round trip), so "identical" is checked on
  parsed data with a 1e-9 relative tolerance.
- **Time at 1×.** Only the game minute is saved; sleep / pause /
  fast-forward never survive a load; water shut-off and the day derive
  from the clock. Item ages use TimeManager's epoch, so it does not
  matter that containers are restored before the clock.

## Numbers

- Acceptance save ≈ 10 KB, 2 ms; load ≈ 0.28 s headless.
- 200 living zombies + 20 corpses: ~71 KB, save 5.3 ms (median of 3),
  load 0.37 s incl. a 145 ms navmesh bake (budgets 200 ms / 3 s).
- Screenshot run: quick-load 0.5 s (with rendering); mean pixel
  difference between the before-save and after-load shots 0.0027.
- Tests: unit 180, integration 221 (shards 111 + 110), all passing;
  `test_acceptance.gd` ≈ 70 s (shard B ≈ 350 s).

## Failed approaches / surprises

- Comparing save texts byte for byte failed on the last digit of doubles
  (facing, item yaw); round-tripping through default-precision JSON was
  not stable either (8.5 % of doubles change on the first round trip).
  → data comparison with tolerance.
- A zombie's yaw read back through `global_rotation` drifts by ~1e-8
  after a basis round trip → keep and save the exact value.
- `Injury.to_dict()` was a UI summary (no timers); a separate
  `save_dict()` / `from_save()` pair keeps it untouched for the HUD.
- `glass_laceration_chance` is 0.4 (not 1.0 as an older doc said); the
  acceptance test seeds the wound rng so the climb always cuts.
- Awaiting a load from the pause menu would resume a freed node → the
  menus fire the load and let the SaveManager (autoload) own the
  coroutine.

## Top remaining issues

See KNOWN_ISSUES "Round-10 save / load gaps": simplified zombie AI state
on load, saving refused while busy, hotbar ghost slots cleared, no
loading screen / confirmation / thumbnail, one-file-per-map (streaming
needs per-chunk records).

## Critic round (all 15 findings fixed in place)

1. **New game in House A**: `WorldConfig.prepare_new_game` puts the player
   at the map's `PlayerStart` (living room) + starter kit (spare t-shirt);
   `SaveManager.new_game / instantiate_new_game(map, seed)`.
2. **Loot guarantees without per-seed hacks**: map-placed hammer on the
   garage workbench; bathroom cabinet ≥ 1 dressing on 92.45 % of 2000
   seeds (measured with LootResolver); "Tear into rags" on clothing
   (t-shirt 3, jacket 4, socks 1) and corpses carry t-shirts / jackets.
3. **Zombies within earshot**: spawner `near_count` 2 in a street zone
   8–13 m from House A; the other 8 spawn ≥ 25 m from the player.
4. **Unstaged acceptance** on seeds 1337 / 7 / 99 (`test_unstaged_*.gd`,
   bot in `acceptance_bot.gd`): new game, default zombies, no item
   injection, no stat forcing, only game time advanced; teleports only
   when walking is stuck (reported; last runs: 0–1, "walk corpse").
   Getting it to pass needed GAME fixes, not test hacks: zombies tumble in
   after a window climb (PZ, 1.4 s down), bites bleed 60 s instead of 180
   (36 hp of bleeding per bite made multi-zombie fights fatal), window
   nav links moved to navigation layer 2 (survivor paths never route
   through a window), and the random zombies keep 25 m from the start.
   The staged variant stays as `test_acceptance.gd` (save / load focus).
5. **Autosave** skips any wake with a reason and any danger
   (`Danger.threat_reason`, 15 m).
6. **Two-phase load**: `SaveSchema.check` types every field before anything
   changes (33 tampered cases in `test_save.gd`, 5 through the real load
   path in `test_save_scene.gd`); the saved map must be an allow-listed
   `res://maps` scene with a WorldConfig; `load_state`s still clamp.
7. **Security**: no `load()` of save-provided paths (items by ItemDB id —
   the `path` key is gone; profiles via `ZombieProfile.registry()`; map
   allow-list).
8. **meta.json** read through `SaveFile.meta_num / meta_str / meta_dict`.
9. **Sort keys precomputed** (item uid); the real 3000-item cost was
   `add_child(node, true)` (readable names are O(n²): 960 ms → 140 ms);
   3000 dropped items: save ≈ 50 ms, load ≈ 0.7 s (perf check added).
10. **Ids from data**: explicit `id` on every room / opening / furniture
    entry of house_a / shed_a (container ids kept equal to the old ones,
    so loot seeds did not change), validated unique; explicit `destroyed`
    list; reordering the furniture array → an old save still applies
    (test).
11. **No spurious infection events** on load (`InjuryComponent.restoring`,
    stage settled silently after the stats).
12. **Slots**: "" refused; injective `_xx` encoding (no collisions).
13. **Hotbar ghosts persist**: items keep their `uid` in every save
    record; hotbar refs are `{uid}` and resolve through the map's item
    index (containers, corpses, floor).
14. **Test saves** in `user://test_saves` (automatic for the test runner,
    screenshot run and perf probes).
15. **UX**: named slots (SlotBrowser) in the pause menu and title screen
    with overwrite / delete confirmations, a "Loading…" overlay, and
    "Unsaved progress will be lost" on quick-load / quit when the last
    save is > 2 game minutes old.

Shards: the integration suite now runs as `integration-a..d` (≈ 275–355 s
each).
