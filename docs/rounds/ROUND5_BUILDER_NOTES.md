# Round 5 — builder notes (containers, data-driven loot, loot window)

## Starting point

The tree held an uncommitted, interrupted Round-5 attempt (static
`ItemDB` class, `Inventory`, `WorldContainer`, `LootGenerator` with a
half-life `LootSettings`, a `PlayerInventory` node). It was reused where
sound and reshaped to the round spec: `ItemDB` is now an autoload
(`items/item_db.gd`), `Inventory` → `ItemContainer`
(`inventory/item_container.gd`), `WorldContainer` → `LootContainer`
(`interaction/loot_container.gd`), `LootGenerator`/`LootSettings` →
`LootResolver` (world-age formula from the spec), the player's inventory
is a plain `Player.inventory: ItemContainer` (no child node).

## What was built

- **Items as data**: `ItemData.category` is an enum (`Category`, 9
  values, `category_id()`), plus `tags`, `description`. `FoodData`,
  `MedicalData` (bandage_quality, rebleed_chance/after, disinfectant,
  pain_relief, splints), `ContainerItemData`. 41 `.tres` under
  `data/items/<category>/` (39 lootable; fists / shove tagged
  `internal`). `ItemDB` autoload: recursive scan, `push_error` on a
  duplicate id, `find_duplicate_ids()` (pure).
- **Loot**: `LootTable` (entries with weight / count / chance / rarity,
  rolls, empty chance, condition range, `validate`), `LootResolver`
  (static: `roll`, `age_multiplier` = max(0.2, 1 − age/60),
  `effective_chance`, `seed_for`, `table_candidates` fallback chain),
  `LootTableDB` (recursive, path ids, `resolve`). 14 tables in
  `data/loot/` incl. `garage/tool_crate`, `zombie_corpse`,
  `convenience_store_shelf`, `default`.
- **Containers**: `LootContainer` — lazy seeded roll on first open,
  `searched`, 1 s / 0.5 s rummage (actor-owned busy tween, 3 m noise,
  interrupted by damage), lid / door tween, Close, auto-close > 2 m,
  `take/put/take_all/put_all` with `item_transferred(from, to, item)`,
  `to_dict/from_dict`, self-built blockout. `ZombieCorpse` extends it.
  `WorldConfig` node ("World": seed 1337, age 0) + `WorldState`
  (persist registry, kept from the earlier attempt for Round 10).
- **Placement**: plan rooms carry `room_type`; `furniture` entries →
  `FurnitureCatalog` (`data/buildings/furniture_catalog.tres`). House A
  got 11 pieces / 8 containers; new `shed_a.tres` "Garage" at (6, −16)
  with a tool crate + shelf + workbench; a standalone Supply crate.
  Furniture sits clear of every door swing, window and test position of
  Rounds 2–4 (teleports, climbs, nav path).
- **Player**: `inventory` (15 kg), pickup into it, X cycles its weapons,
  unequip when a weapon leaves it. Bandaging consumes the best dressing
  ("No bandages"); a rag heals ×1.5 instead of ×2 and 50 % of the time
  reopens after 60 s (`wound_reopened`).
- **UI**: `ui/inventory/loot_window.tscn` (CanvasLayer 2, built in
  code) — ref-4 top bars with lists; HUD timed-action bar, new notices,
  Tab hint. Input action `toggle_inventory` (Tab).

## Tests

- Unit: `test_inventory.gd` (ItemDB catalogue ≥ 25 items, every
  category, descriptions, unique ids; ItemContainer stacking, capacity,
  remove, transfer, split, dict round trip), `test_loot.gd` (all tables
  valid, determinism, 10 k-roll weight / chance / rarity / empty /
  count distributions, world-age thinning + subset property, condition
  items, fallback chain).
- Integration `test_loot_scene.gd` (13): placement (≥ 8 containers,
  layers, ids, garage table), open cabinet → rummage busy + HUD bar →
  items = fixed + seeded roll → window, reopen = same instances, shift /
  click / Loot All / Transfer All / real mouse click on a row (no attack
  fired), capacity greying + refusal, damage interrupts rummaging,
  walk-away + E close, Tab panel, same seed across two fresh scene
  loads (8 containers) and a different seed differs, corpse search,
  bandage consumption / "No bandages" / return on interrupt, rag
  rebleed, pickup into inventory + X cycle + unequip on store.
- Updated: R3 corpse test (search now enabled), R4 combat tests
  (`held_items` → `inventory`, bandages granted in setup).
- Screenshots `19_loot_window` (kitchen cabinet open after a real mouse
  click moved a stack), `20_corpse_loot`; the R4 bandage step stages two
  bandages first.

## Numbers

`scripts/test.sh`: 180 tests, 0 failed. `scripts/perf.sh`: calm 2.6 ms,
hostile 5.6 ms (budgets 8 / 10). `scripts/screenshots.sh`: OK.

## Failed approaches / gotchas

- The seeded kitchen cabinet `HouseA/kitchen/0` rolls empty with world
  seed 1337 (10 % empty chance); the screenshot run previews rolls with
  `LootResolver` (no state change) and opens the first non-empty kitchen
  cabinet instead.
- Mouse clicks injected with `Input.parse_input_event` need window
  coordinates: `viewport.get_final_transform() * control_rect_centre`
  (canvas_items stretch), plus `button_mask`.
- After a rummage finishes the interaction target is recomputed on the
  next physics tick (it is null while busy) — tests wait two frames.
- Food / drink were `max_stack = 1` in the earlier attempt, giving one
  row per can; consumables now stack (beans 10, soda 6, …).

## Open (see KNOWN_ISSUES "Round-5")

No encumbrance / equipment / worn bags (R6); rows are stacks (no
grouping, drag & drop, context menu, drop); window overlaps the room
label; flat rummage noise; no refills; no furniture overlap validation.

## Critic fixes (second pass)

All 13 findings fixed: `Player.can_release_item` (Mid-swing) in every
outgoing transfer; `remove(item, 0)`; `from_dict` count / capacity
guards; weak `owner_container` back-ref + "Already in another
container"; per-roll sub-rng in `LootResolver` (500-seed age-40 ⊆ age-0
multiset test incl. condition items); rows bound to ItemInstance +
pooled (double-press test); corpse ids = spawner path + counter (two
spawners on one seed test); dressing dropped when the pack is full /
refunded when the wound vanished; loot retuned (house 5–11 pickups over
50 seeds, corpse bandage ≈ 5 %, kitchen cabinets are food pantries so
the showcase `HouseA/kitchen/0` has food on seed 1337 — the screenshot
preview hack is gone); `LootContainer` split into `ContainerAccess`
(rummage + transfer rules) and `ContainerVisual` (mesh + lid);
`LootTableDB` is an autoload; Type column; "kg" on both headers; the
HUD room label moved bottom-left. `item_transferred` already emitted
(from, to, item). Not done: grouping identical non-stackables.
