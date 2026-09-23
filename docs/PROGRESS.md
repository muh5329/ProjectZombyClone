# Progress Log

One entry per gauntlet round, newest first. Scores are the verifier rubric
(0–10). "Critic" refers to the independent reviewer pass (a separate agent
that did not write the code).

---

## Round 10 — Save/restore the micro-world, menus, natural-play acceptance (2026-09-23)

### Goal
Persist the whole world as data (never scenes), add save/load UX, and
prove the brief's Final Acceptance Test — first staged, then in natural
play.

### What changed
- `SaveManager` autoload (named slots, quick-save F9 / quick-load F10,
  atomic writes with `.old` fallback, versioned schema + migration hook,
  autosave on safe wake-ups and every 30 real minutes).
- Two-phase load: `SaveSchema` type-checks and sanitises every field
  before anything changes; items by ItemDB id, zombie profiles by
  registry id, maps from an allow-list — nothing is `load()`ed from save
  paths. Map reloads fresh, static objects restored, navmesh baked, then
  dynamic records (zombies, corpses, dropped items, blood, spawners) and
  the player applied.
- Saveable contract with ids from data (explicit ids in BuildingPlans);
  only explicitly destroyed objects are removed on load.
- Menus: title screen (New game / Continue / Load / Quit) as main scene,
  Esc pause menu, slot list with overwrite/delete confirmations,
  Loading overlay, unsaved-progress prompts.
- Natural-play fixes found by the critic: new game starts inside House A
  with a spare t-shirt; clothing tears into rags; a hammer on the garage
  workbench; bathroom dressings on ~92 % of seeds; 2 zombies start within
  earshot; window-climbing zombies tumble in (1.4 s); bites bleed 60 s.
- Tests: `test_acceptance.gd` (staged, save/load focus) and
  `test_unstaged_{1337,7,99}.gd` driven by `acceptance_bot.gd`: real new
  game, map zombies present, no item/stat injection, only time advanced.

### Tests performed
Unit **184**; integration shards a/b/c/d **49/32/70/82** — **417 tests, 0
failed**. Screenshots OK (34_pause_menu, 35_main_menu, 36_before_save /
36_after_load). Perf: save 5.6 ms / load 368 ms with 200 zombies; 3000
dropped items save 49 ms / load 694 ms; zombie budgets still met.

### Bugs discovered (critic) → all fixed
Autosave during danger; tampered saves half-applied with SCRIPT ERRORs,
NaN positions, 1e12 stacks; arbitrary file load from save paths (code
execution risk); bad meta.json crashing the menu; O(n²) dropped-item
save; build-order ids deleting furniture from old saves; spurious
infection event on load; slot-name collisions; hotbar ghosts lost; tests
sharing the real save folder; the acceptance loop impossible in natural
play (no hammer/dressings on the map, road spawn, zombies out of earshot).

### Verifier score (after fixes; critic pre-fix in brackets)
Functionality 8.5 (7) · System Integration 8.5 (7) · Survival Depth 7.5 (4) ·
Architecture 8.5 (7) · Performance 8.5 (8) · UX/Feedback 7 (5) ·
Bug Resistance 8.5 (5).

### Known after Round 10
Hotbar ghost icons render as empty slots after load in 36_after_load
(entries persist, icon lookup doesn't). Combat randomness can still kill
the acceptance bot on an unlucky roll.

### Next action (per brief)
STOP: full vertical-slice review before expanding the world.

---

## Round 9 — Barricading, furniture blocking, carpentry (2026-09-23)

### Goal
Let the player fortify a safehouse PZ-style: nail planks over doors and
windows at the cost of loud hammering and scarce planks, block doors with
furniture, and have zombies physically break through.

### What changed
- `BarricadeData` (data/barricades/wood_planks.tres) + `BarricadeComponent`
  on doors/windows: up to 4 planks, 60 hp each (outermost first), needs
  hammer + plank + 2 nails, 3 s per plank, 18 m hammering noise; blocks
  opening/climbing, ≥2 planks block vision, ×0.8 sound per plank; planks
  darken/crack, break with splinters and noise. Remove with crowbar (2 s)
  or hammer (4 s), partial material return.
- `TimedWork`: single cancel path for all timed jobs (hit, walking off,
  Esc, pressing the action again); eating uses it.
- Furniture: "Block door" (same room, LOS, clear spot; layer 9 so
  doorways stay walkable while zombies smash it, 160-260 hp) and
  "Take apart" for planks/nails (unsearched loot drops). Navmesh
  re-bakes when furniture moves.
- Zombies: breakable contract for barricades, ≤3 attackers per opening,
  queues 1.6 m back, seeded detours; `EntryPlanner` prices windows (nav
  links, `climb_window` state) and doors with a per-building cache.
- `SkillComponent`: carpentry XP/levels (−5 % build time, +5 % plank hp
  per level). Nails box opens into 50 nails; nails scarcer.
- HUD notices ("Hammering is loud!", "A plank gave way! (N left)",
  "Carpentry 1 ↑"), noise meter holds for the sound's duration.

### Tests performed
Unit **165**, integration-a **93**, integration-b **124**, 0 failed.
Screenshots OK (31_barricaded_window, 32_zombies_breaking_in,
33_hammering). Perf: calm 4.0/6.6, hostile 7.6/12.2, noisy 3.9/6.4,
horde 1.4/3.9 ms. Breach of a fully boarded House A: 1 zombie ≈ 139 s,
10 zombies ≈ half that (critic measurement before crowd fix: 70 s).

### Bugs discovered (critic) → all fixed
Materials + XP lost when the plank was refused at the end of hammering;
jobs couldn't be cancelled by walking away; crowds stalled at a
barricaded door (max 2 attackers of 10); furniture snapped through walls;
planks nailed over a mid-climb zombie; disassembly destroyed loot;
from_dict before _ready crashed; dead nails-box loot; misleading noise
meter; moved furniture ignored by navigation.

### Verifier score (after fixes; critic pre-fix in brackets)
Functionality 8.5 (7) · System Integration 8.5 (8) · Survival Depth 8 (7) ·
Architecture 8.5 (8) · Performance 8 (8) · UX/Feedback 7.5 (6.5) ·
Bug Resistance 8 (6).

### Highest-priority remaining issue
Nothing persists: Round 10 (save/restore of the entire micro-world) is the
last round of the vertical slice.

---

## Round 8.5 — Character and vehicle models (owner request) (2026-09-23)

### Goal
Replace capsules and boxes with real-looking people, zombies and cars in
Project Zomboid's style (used as a style reference only — no PZ assets).

### What changed
- Fully procedural, owned assets (no downloads; see docs/ASSET_CREDITS.md):
  `characters/models/humanoid_builder.gd` — 1.75 m skinned humans, 17
  bones, ~600-800 tris, faces (eye sockets, nose, jaw), chunky PZ-like
  proportions; 14 outfits as data (civilians, police, firefighter,
  construction, doctor, nurse, jogger, office, player survivor).
- Zombies: same pool, grey-green skin, torn sleeves, 3-shade blood capped
  at 35 % torso, open mouths, hunched/limping shamble; 48 shared looks
  stratified so every outfit appears; per-zombie height; eye-glow mood.
- 31 code-built animations (idle/walk/jog/sprint/sneak/swings/shove/climb/
  eat/sleep/death/hit; zombie shamble/chase/lunge/bang/knockdown/get-up/
  death) driven by a visuals-only `CharacterAnimator`; LOD update rates
  with hashed phases. Weapon on the hand bone, bag with straps on the back.
- Vehicles (`vehicles/`, data/vehicles): sedan, wagon, pickup, van, police
  sedan, fire pickup; dirt, rust, flat tyres, glass bands; trunk/glovebox
  loot; collision + navmesh; emergency light pools at night (≤4).
  Test map: 7 parked vehicles along a lined road.
- Muted palette (exposure 0.85), subtle hit tint + blood spray, faded
  vehicles capped at 50 % opacity. `CharacterAssets` / `VehicleAssets`.
- Test runner gains `--shard=K/N`; `scripts/test.sh integration-a|b`.

### Tests performed
Unit **153**, integration **198** (two shards 268 s + 280 s), 0 failed.
Screenshots OK (28_characters_closeup, 29_street_vehicles,
30_night_street, refreshed 11/12). Perf: calm 3.7/5.7, hostile 7.1/11.0,
noisy 3.7/6.2, horde 1.3/3.6 ms (avg/p99).

### Bugs discovered (critic) → all fixed
Odd-only spawner seeds used half the zombie looks (some outfits never
appeared) and collapsed the animation LOD stagger; repeat hits didn't
restart flinch; random look for hand-placed zombies; zombies didn't read
as zombies at default zoom; stick-thin bodies; salmon full-body hit flash;
harlequin blood; toy-like saturated palette; floating/sinking wheels;
x-ray faded cars; no emergency light pools.

### Verifier score (after fixes; critic pre-fix in brackets)
Functionality 8.5 (8) · System Integration 8 (8) · Survival Depth 6 (6) ·
Architecture 8 (7.5) · Performance 8 (8) · UX/Visual fidelity 7.5 (5.5) ·
Bug Resistance 8 (7).

### Highest-priority remaining issue
Round 9: barricading doors and windows (planks, nails, hammer; zombies
attack barricades).

---

## Round 8 — Sound propagation + zombie hearing (2026-09-22)

### Goal
Replace the flat-radius noise stub with a real gameplay sound system:
data-driven categories, wall/door/window attenuation, escape through
openings, priority-based zombie hearing, moan recruitment, player noise
feedback, and systemic hooks (glass, shout).

### What changed
- `SoundManager` autoload + `SoundEvent`, 23 categories in
  `data/audio/sound_categories.tres`, spatial hash of zombie ears; every
  emitter migrated (footsteps, doors, windows, melee, rummage, eat, fill,
  shout, moans). Non-finite input rejected.
- Propagation (`audio/sound_math.gd`): one ray re-cast past up to 5 hits,
  multiplicative factors (wall ×0.5, closed door ×0.6, closed window ×0.7,
  prop ×0.85, openings ×1, floor 0.15); sounds escape/enter buildings via
  open doors and windows in both directions; per-event cache by 1.5 m
  ear cell.
- Hearing: loud (≥0.4) investigate at chase speed, faint → turn + shamble;
  louder-or-equal retarget with decay; investigating zombies moan (6 m,
  10 s cooldown, ≤2 relays, ≤2 moans per frame). Chasing/stunned/downed
  zombies ignore sound.
- Player feedback: pooled noise rings, HUD noise meter (LOUD ≥10 m, one
  data setting), F4 sound debug overlay with strength labels. H shouts
  (20 m, 6 stamina, 3 s cooldown).
- Glass: smashing leaves shards 1.2 m each side; walking over them
  25 %/s scratch unless sneaking; climbing through glass 40 % laceration;
  "Remove broken glass" 3 s, 3 m noise.
- Sleep wakes through the sound system (strength threshold) or a zombie in
  LOS within 10 m — no more waking through walls.

### Tests performed
Unit **137**, integration **187**, 0 failed (full suite now > 10 min, run in
two halves). `scripts/screenshots.sh` OK (26_noise_rings, 27_debug_sound).
`scripts/perf.sh` with p99 budgets: calm 3.1/6.2, hostile 7.3/14.8, noisy
3.1/5.6, horde-noise 1.1/3.2 ms.

### Bugs discovered (critic) → all fixed
Furniture made sounds louder (two-ray model), 3 walls counted as 2,
sounds starting inside colliders unmuffled (doors), NaN positions
spamming engine errors, stale expired events, one-way opening path,
moan retarget downgrading loud investigations, dead-player shout/meter,
sleep waking through walls, weak glass hazard, cheap shout kiting,
no worst-frame budgets, freed-mesh crash in the cutaway code.

### Verifier score (after fixes; critic pre-fix in brackets)
Functionality 8.5 (8) · System Integration 8.5 (8) · Survival Depth 7 (6) ·
Architecture 8.5 (8) · Performance 8.5 (8) · UX/Feedback 7.5 (7) ·
Bug Resistance 8 (6).

### Highest-priority remaining issue
Visual fidelity: characters are capsules and there are no vehicles. The
owner asked for real zombie, survivor and vehicle models (PZ as style
reference) — inserted as Round 8.5 before barricades.

---

## Round 7 — World time, needs, eating/drinking, spoilage, sleep (2026-09-22)

### Goal
Give loot stakes: a game clock, hunger/thirst/fatigue that change
behaviour, consumable food and water with spoilage, sinks, and sleep/rest
that carries risk.

### What changed
- `TimeManager` autoload + pure `GameClock` (1 real s = 1 game min, starts
  1 July 07:00, epoch-based); pause/1×/2×/4× (F5-F8, `,` `.`),
  fast-forward refused while chased and reset on death.
- `DayNightLighting`: sun/ambient by hour; neutral grey night, shadowed
  per-room spotlights and warm window panes at night (ref 3).
- `NeedsComponent` + pure `NeedsMath` (data/survival/needs_profile.tres):
  hunger 2.5/h, thirst 3.5/h awake (half asleep), fatigue; leveled
  moodles with hysteresis and warnings; effects on max stamina, regen,
  speed, swing time, health drain, healing. No-water death ≈ 37 game h.
- `ConsumeAction`: Eat / Eat half / Drink, busy + interruptible, tin opener
  or knife (hand-scratch risk), empty bottles, sinks (Drink / Fill bottle;
  water off from day 14). Hunger derived from kcal/25. Spoilage lazy with
  per-container rate (fridge ×0.25); rolled food is as old as the world.
- `RestComponent` + `RestFurniture`: Sleep (refused if not tired, danger,
  bleeding or a need would go critical), sleep at engine ×8 / 20 game min
  per s so zombies keep moving; wakes on hits, needs drain, zombies ≤10 m.
  Rest triples stamina regen.
- `Character.busy_cancelled` + `cancel_busy()` unify eat/bandage/search/
  sleep cancellation. `EventBus.health_drained`.
- HUD: LCD-style clock with °F/date/speed pips (ref 4), moodles, busy
  verb in the state label.

### Tests performed
`scripts/test.sh` → **288 tests, 0 failed** (~490 s).
`scripts/screenshots.sh` OK twice (23_moodles_clock, 24_night,
25_eating). `scripts/perf.sh` calm 2.4 ms / hostile 5.6 ms. Balance:
House A food averages 3.2 days (30 seeds).

### Bugs discovered (critic) → all fixed
Dying of thirst in your sleep without waking (drains emitted no event);
food lost when dying mid-meal (no busy-cancel ownership); saved food
double-aged depending on load order; unopened containers held fresh food
forever; fill bottle with no room; eating while paused; balance: death in
12 game hours, one house ≈ 1 day of food, unlimited water, sleep safe by
construction; night light bleeding through walls.

### Failed approaches
- Waking at 8 m: investigating zombies stop ~8 m out → 10 m.
- Unseeded combat rolls in the screenshot run occasionally lost the R4
  fight and cascaded; the runner now seeds combat/injury RNGs.

### Verifier score (after fixes; critic pre-fix in brackets)
Functionality 8 (7) · System Integration 8 (7) · Survival Depth 7.5 (5) ·
Architecture 8 (7) · Performance 9 (9) · UX/Feedback 7.5 (6) ·
Bug Resistance 8 (6).

### Highest-priority remaining issue
Noise is a flat radius; Round 8 (sound propagation + zombie hearing,
walls/doors attenuation, noise UI) is next.

---

## Round 6 — Inventory, equipment, bags, encumbrance (2026-09-22)

### Goal
Make carrying a decision: equipment slots, wearable bags with weight
reduction, drop/pick-up, hotbar, a full inventory screen, and encumbrance
that feeds speed, stamina, sprint and noise.

### What changed
- `Equipment`: primary/secondary hand (two-handers take both) and back;
  each slot is an `ItemContainer`, so equipped items leave the pack and
  weight counts once. `MeleeCombat` mirrors the primary hand. X cycles
  weapons. `inventory/hotbar.gd`: 3 slots, keys 1-3 work with any
  modifier; interaction alternatives moved to keys 4-7.
- Bags: `ContainerItemData` capacity + weight reduction (school bag 7 kg,
  −30 %; duffel 18 kg, −40 %, 1.8 kg, ×0.97 speed while worn). Nesting
  and cycle rules enforced in the model; nested weight watched at any
  depth. Bags on the ground open as containers. G drops to a `WorldItem`.
- `Encumbrance` (pure): ok ≤8 / light ≤12 (×0.92, +15 % drain) / heavy
  ≤15 (×0.85, +30 %, footsteps ×1.2) / overloaded (×0.65, +70 %, no
  sprint). Recomputed once per frame; events only on real changes.
- Inventory screen (Tab) with container tabs, categories, equipped section,
  context menu (Equip/Unequip/Drop/Use/Assign hotbar), Ctrl-split,
  drag-and-drop; "Space W/Cap" vs "Carrying X / 8 kg"; hotbar widget.
  Loot window split into panel/menu/drag-drop pieces with diffed rows.

### Tests performed
`scripts/test.sh` → **236 tests, 0 failed**. `scripts/screenshots.sh` OK
twice in a row (21_inventory_screen, 22_overloaded). `scripts/perf.sh` calm
2.6 ms / hostile 5.8 ms; 400-row refresh ≈ 7 ms, Loot All 199 ≈ 2 ms.

### Bugs discovered (critic) → all fixed
Hotbar dead while Shift/Ctrl/Alt held (Alt collided with walk);
encumbrance state flicker mid-operation; save could load a two-hander
next to a primary weapon; clicking the world with the inventory open
attacked; loot API could stuff any item into a hand; stale nested-bag
weight; 80+ ms UI refresh and a 199-event Loot All storm; dressing and
worn-bag return paths; hotbar forgot dropped items; school bag
overpowered; two confusing capacity numbers; two save formats.

### Verifier score (after fixes; critic pre-fix in brackets)
Functionality 8 (8) · System Integration 8 (7) · Survival Depth 7 (6) ·
Architecture 7.5 (7) · Performance 8.5 (6) · UX/Feedback 7 (6.5) ·
Bug Resistance 8 (7).

### Highest-priority remaining issue
Food and drink are inert. Round 7 (hunger/thirst + eating/drinking) gives
loot its stakes.

---

## Round 5 — Containers and data-driven loot (2026-09-22)

### Goal
Physical containers that are searched (PZ-style lazy roll), data-driven
items and loot tables keyed by building/room/container, a player
inventory, and the ref-4 two-panel loot window.

### What changed
- `ItemData` categories/tags/description; `FoodData`, `MedicalData`,
  `ContainerItemData` stubs; 41 items in `data/items/**`; `ItemDB`
  autoload (recursive scan, duplicate-id errors).
- `LootTable` (weights, chances, count ranges, rarity tiers) + pure seeded
  `LootResolver` (world age only removes, via per-roll sub-RNGs);
  14 tables with fallback container → room → building → default;
  `LootTableDB` autoload. Loot tuned for scarcity (House A averages
  5–11 items over 50 seeds; about a third of containers empty).
- `ItemContainer` (stacking, split, capacity, ownership back-ref,
  to/from_dict with validation); `ContainerAccess` (rummage 1 s / 0.5 s,
  interruptible, transfer rules incl. `Player.can_release_item` mid-swing
  guard); `ContainerVisual`; `LootContainer` glue. Corpses are containers
  with unique ids.
- Furniture from `BuildingPlan.furniture` (catalog resource): House A has
  11 pieces / 8 containers; new garage with tool crate and shelf; supply
  crate outside. `World` node holds seed + world age.
- Player inventory 15 kg replaces R4 `held_items`; B consumes bandage/rag
  (rag may reopen after 60 s); "No bandages" refusal.
- `LootWindow` (ref 4): Inventory · Transfer All · W/15 kg on the left,
  Loot All · container · W/Cap kg on the right; Name/Type/Qty/kg/Cond
  columns, pooled rows bound to items, click/shift-click, "Too heavy".

### Tests performed
`scripts/test.sh` → **188 tests, 0 failed**. `scripts/screenshots.sh` OK
(19_loot_window, 20_corpse_loot). `scripts/perf.sh` calm 2.6 ms / hostile
5.6 ms.

### Bugs discovered (critic) → all fixed
Stash equipped weapon mid-swing and the hit still landed; remove(0)
removed one; save load created items from count ≤ 0 and ignored capacity;
one item could live in two containers (dupe risk); world age reshuffled
loot instead of only removing it; loot rows bound to indices (double
press moved two stacks); duplicate corpse ids across spawners; lost
dressing on interrupted bandage; flat, over-generous loot; LootContainer
god object; UI covered the room label; missing "kg"/type column.

### Verifier score (after fixes; critic pre-fix in brackets)
Functionality 8 (8) · System Integration 8 (7) · Survival Depth 6 (5) ·
Architecture 8 (7) · Performance 9 (9) · UX/Feedback 7 (7) ·
Bug Resistance 8 (6).

### Highest-priority remaining issue
Weight has no consequence yet and bags don't exist: Round 6 (inventory,
equipment slots, backpacks, encumbrance → movement) is next.

---

## Round 4 — Melee combat, shove, body-region injuries (2026-09-22)

### Goal
Let the player fight back without becoming a superhero: data-driven melee
weapons, aim/charge, shove crowd control, body-region injuries with
bleeding/pain/infection, bandaging, and pickup/equip of weapons.

### What changed
- `ItemData`/`WeaponData`/`ItemInstance`; weapons as .tres (bat, crowbar,
  knife, hammer, pipe, fists, shove). `WorldItem` pickups (bat in living
  room, knife in kitchen), X cycles weapon (refused mid-swing).
- `MeleeCombat` facade over `SwingStateMachine` (queue/charge/phases) and
  `HitResolver` (arc query + LOS on layers 1/7/8, damage × charge × pain ×
  exhaustion, head hits, knockback, knockdown, wear on the swung
  instance). Tuning in `data/combat/combat_profile.tres`.
- Aim (RMB) faces the mouse on the ground in ortho, caps speed to walk,
  shows a reach ring + "N in reach"; hold LMB to charge (×0.6→1.3).
- Shove (Space) 1.0 m/90°/3 targets, cancels zombie windups.
- Zombies: `KnockedDown` state (×1.5 damage while down), stagger threshold
  16 with 1.2 s immunity, windup 0.4 s, range 1.0 m.
- `InjuryComponent`: 10 regions, scratch/laceration/deep wound/bite/burn/
  fracture, bleeding drain, leg slow, max-stamina reduction, pain (>50 /
  >80 slows and weakens swings), infection hidden until symptoms
  (Feverish ≥25, Infected ≥60). B bandages worst bleeding wound (4 s,
  interrupted by damage). Smashed-window climb lacerates.
- HUD: weapon + condition, injuries list, pain, charge meter, bandage
  progress, "Idle", stamina "· max N %"; pooled blood decals.

### Tests performed
`scripts/test.sh` → **154 tests, 0 failed** (70 unit, 84 integration;
watchdog raised to 900 s). `scripts/screenshots.sh` OK (14_aim_arc,
15_swing_hit, 16_knockdown, 17_injury_panel, 18_bandaging).
`scripts/perf.sh` calm 4.15 ms / hostile 7.75 ms. Balance bot (seeds 1-5):
1v1 bat costs 12-27 % health (avg 23 %); 3 zombies kill a static bot every
seed; a non-fighting surrounded player dies < 30 s.

### Bugs discovered (critic) → all fixed
Stale queued swing after an interrupted windup (double swing, double
stamina, double charge rate); weapon swap mid-swing skipped wear
(infinite-durability exploit); knockdown cancelled its own knockback;
blood decals at fixed height; damage didn't interrupt bandaging; B
"bandaged" fractures; 1v1 bat stun-lock (0 % health lost); instant green
"INFECTED" spoiler; pain had no effect; freed zombies held attack slots
(found during fixing); melee_combat.gd god object; tuning outside data;
balance test with no lower bound.

### Verifier score (after fixes; critic pre-fix in brackets)
Functionality 8 (7.5) · System Integration 8 (8) · Survival Depth 7 (5.5) ·
Architecture 8 (7) · Performance 8 (8.5) · UX/Feedback 7 (6) ·
Bug Resistance 8 (6.5).

### Highest-priority remaining issue
No loot: weapons are placed by hand and bandages are free. Round 5
(interactable containers + data-driven loot tables) is next.

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
