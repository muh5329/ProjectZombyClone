# Round 8.5 builder notes — real people, zombies and vehicles

Owner request: "add real zombie models, real people models and real
vehicles; reference Project Zomboid for references".

## Route taken: fully owned procedural geometry

No assets were downloaded. The procedural route was chosen over hunting
CC0 rigged packs (Quaternius / Kenney mirrors on GitHub) because:

- **Licence risk is zero** (see `docs/ASSET_CREDITS.md`: no third-party
  assets). PZ is only the style reference.
- **One consistent style** for people, zombies and cars, readable at the
  dimetric default zoom (~75 px tall people).
- **Clothing as data** (`Outfit` .tres) on one shared skeleton — a pack
  would give a few fixed characters, not "townspeople in varied clothes".
- **Performance control**: one vertex-coloured skinned mesh per look (2
  draw calls per person), meshes shared per look, clips shared, manual
  AnimationPlayer ticking with LOD.

## What was built

| Piece | Files |
|---|---|
| Outfit data (14) | `characters/models/outfit.gd`, `data/characters/outfits/*.tres` |
| Look (outfit + skin + hair + decay) | `characters/models/appearance.gd` |
| Humanoid mesh + 17-bone skeleton + skin | `characters/models/humanoid_builder.gd` |
| 31 procedural clips | `characters/models/character_animations.gd` |
| Model node (skeleton / mesh / AnimationPlayer) | `characters/models/character_model.gd` |
| Player animator (+ bag on back) | `characters/models/character_animator.gd` |
| Shared resources node | `characters/models/character_assets.gd`, `vehicles/vehicle_assets.gd` |
| Zombie visual rewritten on the model | `zombies/zombie_visual.gd` (+ `zombie.gd` calls `animate`, `zombie.tscn` Visual is a Node3D, `zombie_corpse.gd` box) |
| Weapon on the right-hand bone | `combat/melee_visuals.gd` |
| Vehicle data (6) | `vehicles/vehicle_data.gd`, `data/vehicles/*.tres` |
| Vehicle mesh builder | `vehicles/vehicle_builder.gd` |
| Parked vehicle + trunk / glovebox | `vehicles/vehicle.gd`, `vehicles/vehicle_container.gd`, `data/loot/vehicle_trunk.tres`, `data/loot/vehicle_glovebox.tres` |
| Night lights hook | `world/day_night_lighting.gd` (group `day_night`, calls `set_night_lights`) |
| Map | `maps/test_ground.tscn`: box "Car" removed, 7 vehicles, road centre line |
| Player scene | `player/player.tscn`: capsule + nose removed → `Visual/Model` + `Animator` |
| Dev preview tools | `tests/tools/model_preview.gd`, `tests/tools/street_preview.gd` |

Budgets: people 584–764 triangles (unit-tested 300–800), vehicles
486–582; building one person mesh ≈ 3.5 ms (48 zombie looks are built
lazily as zombies spawn).

## Design notes / gotchas

- **Winding**: Godot front faces are clockwise seen from the front;
  `VehicleBuilder._tri` flips a triangle whose (b−a)×(c−a) points along
  the wanted normal, so every generator can emit in any order.
- **Vertex colours** need `vertex_color_is_srgb = true` to match the
  sRGB albedo values in the data; the early previews were washed out
  until the skin tones were retuned for the game's bright sun + filmic
  tonemap.
- **Blood** is chosen per triangle from a hash of a coarse 11 cm grid —
  per-vertex colours smeared into pink gradients; per-triangle random
  gave a harlequin pattern.
- **`@onready` of the parent is not set in a child's `_ready`**: the
  animator looks up `Health` by path (this cost a failing "hit flinch"
  test).
- **Order on death**: `Zombie.die()` runs `ai.on_death()` (leaving
  knocked_down → `set_knocked_down(false)` → z_getup) before the corpse
  adopts the visual, so `collapse()` also trusts `is_lying()`; a zombie
  killed on its back stays there instead of standing up to fall again.
- **CharacterAssets** is added to the root with `call_deferred` (the player
  model asks for it while the map is being added) and cached in a static
  Node reference (not a Resource → no leak report).
- **Lunge**: the old code offset the visual in the *parent's* −Z (not
  the facing); the offset now moves the model inside the rotated visual.
- Vehicles use the existing layers: body 1 + 6 (navmesh-baked, blocks,
  fades), containers 4 with prompts outside the body (the interaction
  LOS ray treats the car as the container's ancestor anyway).

## Tests

- Unit `tests/unit/test_models.gd` (11): skeleton, outfits valid / ≥ 10 /
  required roles, triangle budget + skinning + height for every outfit
  (human and zombie), outfit application (shirt / sleeves / pants /
  jacket / cap by bone), determinism per seed + variety, zombie look
  (desaturated, blood, torn sleeve), clip library (31 clips, tracks,
  loops, lying death), animator / zombie clip choice, vehicle data valid,
  builder dimensions / surfaces / tri budget per type, variation
  determinism + palette variety, open pickup bed.
- Integration `tests/integration/test_models_scene.gd` (10): player
  model + idle / walk / jog / sneak / sneak_idle and moving bones; weapon
  on hand_r, 2h windup / strike clips, the bat moves with the arm, 1h for
  the knife; bag on the chest bone; hit flinch; death pose lies;
  zombie chase → z_chase, knockdown → z_knockdown + lying, corpse pose
  persists (no pop-up when killed down), standing death → z_death;
  crowd variety with shared meshes; vehicles present / layers / shapes /
  police; trunk + glovebox searchable with the vehicle tables, pickup
  "Search truck bed"; the van blocks the player; the navmesh path goes
  around a car; police lights on at night / off by day, civilians dark.
- Updated: `test_combat_scene` knockdown / get-up checks (clip + pose
  instead of `rotation.x`), `test_zombie_scene` corpse / eye tint checks.
- Screenshots: new `28_characters_closeup`, `29_street_vehicles`;
  11 / 12 (and every other shot) now show the models.

## Perf (scripts/perf.sh, this 2-core box)

| Mode | Before (R8) | After (R8.5) | Budget |
|---|---|---|---|
| calm / loud avg | 3.23 ms | 3.77–4.07 ms (p99 6.2–7.2) | 8 / p99 16 |
| hostile avg | 5.91 ms | 7.13–7.46 ms (p99 11.5–12.0) | 10 / p99 16 |
| noisy avg | 3.06 ms | 3.75–3.88 ms (p99 6.7–6.8) | 10 / p99 16 |
| horde-noise avg | 1.10 ms | 1.28–1.72 ms (p99 3.5–6.8) | 10 / p99 20 |

Idle-frame process time with 200 models ≈ 0.8–1.4 ms (new informational
line; skeleton updates run there).

## Next

Upper/lower body layering (AnimationTree with bone filters) so swings
blend with walking; clothing items linked to outfits (wear / loot the
dead cop's badge); driving (VehicleBody3D over the same builder);
headlight SpotLights with a light budget; animation manager for far
zombies (population sim).

Full runs at the end: `scripts/test.sh unit` 148/148, `scripts/test.sh
integration` 197/197 in 548 s (one call, just under the 10-min cap —
split with `--filter` if the box is slower), `scripts/screenshots.sh` OK
twice, `scripts/perf.sh` OK.

## Critic fixes (second pass)

1. Looks: spawner seeds are all odd (`randi() | 1`) so `seed % 32` used
   16 looks. Now `variant_for_seed = posmod(hash(seed), 48)` over a
   stratified table (every weighted outfit ≥ 2 looks); unit test with
   real `ZombieSpawner.next_seed` draws: 200 spawns → ≥ 30 looks, every
   outfit present. LOD phase = `posmod(hash(seed), 6)` (histogram test).
   Repeat hits restart the flinch (player + zombie); seed-0 zombies seed
   from their node path.
2. Visuals: z_walk / z_chase spine −25°, neck +15°, head droop, arms
   forward, right foot out 20°, lurching limp; flat grey-green skin;
   chunkier bodies, head ×1.15; muted cloth / paint (sat ×0.75, value ≤
   0.75) + tonemap exposure 0.85; blood only chest / collar / lower
   sleeves (3 shades, ≤ 35 % torso, test); eye sockets / nose / jaw for
   everyone, open mouth for zombies; hit = 0.08 s 30 % red tint on the
   body surface + blood spray particles (no salmon override).
3. Vehicles: road dirt, rust patches, glass sky band; flat tyre sags its
   corner only and every wheel touches y = 0 (test; wheel rings now start
   at the bottom vertex — they floated 1.6 cm before); night = beacons +
   one alternating OmniLight (budget 4), parked cars' lamps off; faded
   cars keep alpha ≥ 0.5 + DEPTH_DRAW_ALWAYS (test); darker bag + straps.
4. Architecture: ModelAssets split into `CharacterAssets` +
   `VehicleAssets` (typed dictionaries); per-zombie height on the model
   node (not the shared mesh).
5. Tests: `scripts/test.sh integration-a` / `integration-b` (runner
   `--shard=K/N`, greedy by per-file runtimes): 85 tests / 268 s and
   113 / 280 s. Unit 153, integration 198 — all pass. Screenshots OK
   twice (new 30_night_street; 11 / 12 at the default zoom). Perf: calm
   3.76, hostile 7.10 (p99 10.6), noisy 3.90, horde 1.31 ms — OK.
