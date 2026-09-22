# Round 6 — builder notes (inventory, equipment, encumbrance)

## Decisions

- **Equipped items leave the inventory.** Each Equipment slot is an
  unlimited `ItemContainer` tagged `equipment_slot`. Equipped weight
  therefore counts once, "unequip goes to the inventory or is refused
  when full" is meaningful, and every generic transfer (loot window
  put / drag / drop) works on equipped items without special cases.
  Slot changes from anywhere are seen through the slot containers'
  `changed` → `equipped_changed(slot, item)`.
- **MeleeCombat no longer owns equipment.** `equipped` mirrors the
  primary hand via `Equipment.equipped_changed`; `combat.equip()` stays
  as a convenience that asks the Equipment (so R4 tests that call it
  still pass, and a mid-swing swap is refused by the release guard).
- **Keys:** number keys 1-3 are always the hotbar; interaction
  alternatives are on **keys 4-7** (first pass used Alt+1..4, which
  collided with Alt = walk — fixed after the critic).
- **Capacity reconciliation:** the main inventory is a hard 20 kg
  (`profile.inventory_capacity`), bags add their own capacity (school
  bag 12 kg, duffel 18 kg), and **encumbrance** (carried weight vs 8 /
  12 / 15 kg) is what hurts. The brief's "backpack 0.7" is read as the
  contents multiplier: `weight_reduction` 0.3 → contents count 70 %
  (duffel 0.2 → 80 %). Four states: ok ≤ 8 < light ≤ 12 < heavy ≤ 15 <
  overloaded; "light ≤ 1.0" became ×0.95 speed / ×1.1 drain.
- **Nested access rule:** only the worn bag's contents and bags lying on
  the ground are open-able. A bag inside the main inventory is a
  closed full-weight item — this keeps every container's capacity
  invariant (adding to an inner bag would otherwise overfill the outer
  one silently). Cycle / worn-bag rules live in
  `ItemContainer.accept_reason` and are enforced by `add` and
  `transfer_to` themselves, not just the UI.
- **Two-handed** = `WeaponData.two_handed` (baseball bat). It lives in
  the primary slot; `secondary()` reports it.
- **Pickup when full:** a weapon / tool goes into empty hands, a bag onto
  an empty back (PZ-like convenience; the R5 "pickup refused when full"
  test now covers "full pack AND busy hands").

## What was built

- `inventory/equipment.gd` (Equipment), `inventory/encumbrance.gd`
  (Encumbrance), `inventory/item_actions.gd` (ItemActions),
  `ui/hud/hotbar.gd` (HotbarWidget).
- `ItemInstance`: `contents` for bags, `uid`, `unit_weight()`,
  nested `to_dict/from_dict`. `ItemContainer`: `owner_item()`,
  `equipment_slot`, `accept_reason`, `fit_item`, unit-weight fits.
  `ContainerItemData.capacity_kg`. `WeaponData.two_handed`.
- `StatsComponent.set_drain_multiplier` (negative rates only),
  `FootstepEmitter.set_multiplier`, `Character.set_sprint_lock` +
  `sprint_denied_reason()`; profile "Carrying" group.
- Player verbs (equip / unequip / move / drop / split / use / hotbar /
  cycle across hands + pack + bag), `carried_to_dict/from_dict`.
- `ContainerAccess` is duck-typed on its container node and takes the
  actor-side container explicitly (active tab / item's own container);
  `WorldItem` bags open like containers; `WorldItem.drop()`.
- `InjuryComponent.bandage_worst(preferred)` (Use on a rag uses that
  rag) and searches the worn bag too.
- Loot window → inventory screen: container tab column (loot target),
  equipped-first + category headers, context menu, Ctrl split, G drop,
  drag and drop (rows, lists, panels, tabs), ground bags on the right.
- HUD: carried-weight readout coloured by state + notices, "Too heavy"
  sprint refusal, hotbar bottom-centre; notices moved below the player
  (outlined) so they never sit under the inventory panels; key hints are
  a bottom-right block.
- School bag `WorldItem` on the House A bedroom bed (−10.75, 0.48, −8.1),
  away from every earlier test position.

## Tests

- Unit `test_equipment.gd` (14): thresholds / effects, worn-bag
  reduction, capacity with contents, drain multiplier, footstep
  multiplier, two-handed rules, bag / hand rules, unequip-or-refuse,
  swap frees room from the source, cycle prevention (any depth,
  transfer_to), worn bag never into a bag, nested save round trip with
  hotbar refs, hotbar assign / use / prune, ItemActions.
- Integration `test_inventory_scene.gd` (19): bed backpack → pick up →
  wear → capacity + reduced weight; loot into the bag tab; real jogging
  distance ×0.65 overloaded / ×0.85 heavy over 2 s, footsteps ×1.2;
  stamina drain ×1.7 and sprint "Too heavy" (+HUD red readout);
  encumbrance event + notice; drop → WorldItem on layer 4 → pick up
  again; drop equipped + G on the Tab screen; hotbar via context menu
  + real keys 1/2 (Alt+1 ignored); Alt+N smashes a window, plain N does
  not; Tab screen click selects without attacking and WASD still moves;
  category grouping; Ctrl split (both sides); drag-and-drop payloads
  (tabs, panels, refusal of a bag into itself / full pack); a REAL mouse
  drag (press, 12 motion events with `relative`, release); ground bag
  open / loot / worn bag refused / walk-away close; Use rag / food stub
  / B from the bag; right-click context menu (no aiming); X through
  bag weapons + broken weapon; player carried round trip.
- Updated R4/R5 tests: bat in hands not pack, 20 kg numbers, Transfer
  All leaves the hands, pickup-when-full, "[Alt+2]" prompt text.
- Screenshots `21_inventory_screen` (Tab screen, Inventory + School
  Bag tabs, equipped rows, hotbar with the hammer drawn by key 2),
  `22_overloaded` (sprinting refused "Too heavy", red "Overloaded"
  readout, 2.1 m/s).

## Numbers

`scripts/test.sh`: 221 tests, 0 failed (≈ 400 s). `scripts/perf.sh`:
calm 2.6 ms, hostile 5.8 ms (budgets 8 / 10). `scripts/screenshots.sh`:
OK.

## Gotchas

- `Control.set_meta(k, null)` REMOVES the key and `get_meta(k, null)`
  then raises an engine ERROR (null default = "no default"). Pooled rows
  use `has_meta`.
- GUI drag detection accumulates `InputEventMouseMotion.relative`;
  synthetic motion events without it never start a drag.
- A transfer removes the item (its container's `changed` fires while it
  belongs nowhere) before inserting it: hotbar pruning is deferred and
  `hotbar_item()` filters by `carries()`.
- `InputEventKey` action matching is non-exact by default: an action
  without modifiers also matches Alt+key — use exact matching for the
  hotbar.

## Critic fixes (second pass)

1. Hotbar works with Shift / Ctrl / Alt held (non-exact action match);
   interaction alternatives moved to keys 4-7 ("[5] Smash window").
   Tests: Shift+1 / Ctrl+1 / Alt+1 equip; 2 is not the window, 5 smashes.
2. Encumbrance coalesced (`mark_dirty` → one deferred flush; getters
   flush; emit only when the final weight/state differs). Tests: equip
   from the pack at 15.7 kg → no event; moving into the bag → ≤ 1.
3. `Equipment.from_dict` routes through `equip()` + combo checks
   (two-hander only primary; nothing beside it; bag only on the back).
4. No attack while the inventory / loot screen is open
   (`EventBus.inventory_screen_toggled`) or when the press starts over
   GUI. Test: real world click with the screen open → no swing; closed → one.
5. `ContainerAccess` refuses slot containers as targets ("Use Equip").
6. Nested bags re-emit `changed` recursively (connect on append,
   disconnect on detach); cached weights stay right. Unit + integration.
7. Perf: `ItemContainer` weight cache (incremental), `begin_batch /
   end_batch` (Loot All = one `changed` per side + one encumbrance
   update), hotbar emits only on summary change, keyed row
   reconciliation in `ItemListPanel` (no zebra striping), reason cache.
   `test_inventory_perf.gd`: 400-row refresh after a transfer ≈ 7 ms
   (< 15 asserted), Loot All of 199 stacks ≈ 2 ms (< 60 asserted).
8. Interrupted bandage returns the dressing to its origin container
   (bag), else main, else floor; taking off the worn bag with no room
   drops it with a notice; hotbar keeps references by identity (greyed
   while not carried, works again after pickup); orphan
   `test_zz_dbg.gd.uid` deleted.
9. School bag 7 kg / 0.3; duffel 1.8 kg / 18 kg / 0.4 / ×0.97 worn
   speed; light ×0.92 / +15 %. Load "Carrying X / 8 kg" (HUD + under
   the tabs) vs storage "Space W / Cap kg" (panel headers); worn bag row
   "School Bag 1.4→0.98".
10. Save key unified to `count` (`stack` read as fallback);
   `loot_window.gd` split into `ItemListPanel`, `ItemContextMenu`,
   `InventoryDragDrop` + controller; hotbar → `inventory/hotbar.gd`.

After fixes: 236 tests, 0 failed; screenshots OK; perf OK.

Gotcha: GDScript `get_meta(k, null)` is "no default" (errors when the
key is missing) and `set_meta(k, null)` removes the key — use has_meta.
