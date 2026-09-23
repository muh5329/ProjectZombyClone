# Round 11 — builder notes (procedurally generated starting world)

Owner request: "Build out an entire starting world. It should be randomly
generated with interconnecting roads and buildings that make sense and
fields and small towns and woods etc." Also closes the vertical-slice
review's gaps #1-#3 (neighbourhood, store / warehouse / gas station,
forest, 30-50 zombies).

## What was built

- **`worldgen/`** (new folder, all pure except the builder / nav):
  - `world_gen_params.gd` + `data/worldgen/default_world.tres` — every
    number of the generator as data.
  - `world_layout.gd` — `WorldLayout`, the generated world as plain
    records + zone raster; `to_json()`, `layout_hash()`, `plan_hash()`,
    chunk helpers.
  - `world_generator.gd` — `WorldGenerator.generate(seed, params)`:
    zones → town → hamlets → farmsteads → ponds → road network (A*) →
    buildings → fields → fences → props → vehicles → trees → population.
  - `building_plan_generator.gd` — `BuildingPlanGenerator`: house,
    farmhouse, convenience store, hardware store, pharmacy, diner, gas
    station, warehouse, barn; `rotate_plan`; `check`.
  - `world_layout_validator.gd` — every invariant the tests assert.
  - `world_map_renderer.gd` — layout → Image (map overlay + PNGs).
  - `world_builder.gd` — `WorldBuilder`: layout → chunk nodes.
  - `world_nav.gd` — `WorldNav extends NavBaker`: per-chunk navmesh.
- **`maps/world.tscn`** — the generated county (WorldConfig with
  `worldgen_params`, Generated, NavRegion = WorldNav, Zombies, a 5th camera
  zoom level 44, MapOverlay).
- `interaction/gas_pump.gd` (`GasPump`), `ui/hud/world_map_overlay.gd`
  (`WorldMapOverlay`, M = `toggle_map`), `assets/materials/world_ground.gdshader`,
  `assets/materials/tree_canopy.gdshader`.
- Catalog: `stove`, `store_shelf`, `cooler`, `rack`, `pallet`, `hay_bale`,
  `desk`. Loot: 23 new tables (see SYSTEMS.md), all following the Round-9
  scarcity rules (nails 3-12, nail boxes 10 %), 35-50 % empty.
- Hooks: `ZombieSpawner.spawn_points`, `WorldConfig.worldgen_params`,
  `WorldSnapshot.apply_world_config` + `world.worldgen_params` in the save,
  `SaveManager.load_data` (config before the map enters the tree,
  `focus_on` the saved player before the bake), `SaveSchema`
  (worldgen_params must be a `res://data/worldgen/*.tres`), `MainMenu`
  (New game → world.tscn with a random or typed seed).
- Tests: `tests/unit/test_worldgen.gd` (22), `tests/integration/test_world_scene.gd`
  (13), screenshot run `_round11` (37-43; `SCREENSHOT_ONLY=world` runs it
  alone), `tests/perf/perf_world.gd` (`scripts/perf.sh --world`, also in
  the full perf run). Dev tools: `tests/tools/world_map_preview.gd`
  (`-- [seeds] [--size=] [--mpp=] [--crop=x,y,w,h]`), `world_validate.gd`
  (`-- first count [--plans] [--size=]`, wrapped by
  `scripts/worldgen_sweep.sh`), `world_variety.gd`, `world_loot_census.gd`,
  `world_probe.gd`.

## Critic pass (21 items, fixed in place)

- **Layout**: towns anywhere / any angle, 2-4 × 1-3 blocks with L / T
  shapes, cul-de-sacs, 20-60 lots, continuous shop frontage (+ bar,
  church / post office), parking behind; hamlets (linear / crossroads) on
  the county roads; farms with their own fields; fields only by roads /
  farms; loop road or 2nd highway; curvier rural roads (length / chord
  1.24). Every area record is an oriented box (`xf` + `size`);
  HouseBlockout nodes are rotated (plan normals → world).
- **Roads**: existing road cells are solid for new routes except at the
  new route's own ends; crossings get shared junction vertices; no road
  may run along another; ponds / hamlets never on planned roads.
- **Props / vehicles**: lamps ≥ 2 m from driveways, mailboxes opposite
  the driveway, trash cans / lamps / poles / benches / cars never in front
  of any exterior door, kerb parking ≥ 8.6 m from junctions, rotated
  vehicle boxes vs everything.
- **Validator + tests**: see SYSTEMS (30-seed unit test, 200-seed sweep:
  0 problems; 384 / 512 / 1024 / 1536 / 2048 m sizes clean).
- **Params** scale with the area; 384 m worlds get ≥ 1 hamlet + ≥ 2
  farms (fallback yards / standalone hamlet); 1536 m layout ≤ 1.3 s.
- **Saves** carry `{version, layout_hash}`; mismatches are refused.
- **WorldNav**: verified readiness, no coroutines, freeing / bake-ahead,
  0.1 m cells; spawner retries; rural groups spawn on chunk readiness.
- **Determinism**: component rngs seeded via `WorldConfig.rng_seed_for`;
  the bot's deterministic window cut; the shard weight hack is gone.
- **Loot**: improvised weapons in houses, a hammer per hamlet, food
  thinned to ~140-170 per county.
- **Looks**: olive palette + dirt patches + verges, pitched / hip /
  gambrel roofs, upper-storey look, porches, awnings + signs, silo, hay,
  crop rows per field axis, kerbs, zebra crossings, utility poles, night
  light budget.

## Numbers (seed 1337, 2-core box, headless)

| | |
|---|---|
| World | 768 × 768 m, 12 × 12 chunks of 64 m |
| Content | 59 buildings, ~7.2 k trees, 40 start zombies + 6 rural groups |
| Layout | 0.25-0.34 s at 768 m (≤ 0.45 s over 200 seeds), ≤ 0.15 s at 384 m, ≤ 1.3 s at 1536 m |
| Build | ~1.0 s, ~27 k world nodes |
| Nav | 25 regions, 3.5-4.2 s on worker threads (0.1 m cells) |
| Load | instance → navmesh ready ≈ 6-7 s (budget 20 s) |
| Perf | hostile street: 1.2 ms avg / 8 ms p99 physics; walking 300 m at 6.5 m/s: 0.9 ms avg / 9.4 ms p99 main-thread work (worst 23 ms), 31 regions baked ahead, 20 freed |
| Loot | food 142-171, weapons 37-50 per county (seeds 1337 / 7 / 99 / 42) |

## Decisions

- **Data first, nodes second.** Everything is decided in a pure pass
  (`WorldLayout`); the builder never decides anything. This makes
  determinism testable by hash and lets Round 12 stream chunks from the
  same layout.
- **Stable ids = deterministic generation.** Each stage has its own rng
  (`sub_seed(seed, "town" / "roads" / "trees" / …)`) so a change in one
  stage never shifts another; building ids come from settlement + lot
  order; plans are seeded by `sub_seed(seed, "plan:" + building id)` and
  carry explicit entry ids. A save stores only seed + params; the load
  regenerates the identical world and applies statics by id.
- **Buildings at any angle.** First pass rotated plans as data (quarter
  turns only); the critic wanted towns at any angle, so HouseBlockout now
  rotates its plan's wall normals into world space (`outward` stays a
  world vector for the cutaway / sound / entry planner) and nodes carry
  the lot transform.
- **Town as a grid, countryside as A*.** The town is an axis-aligned
  grid in a local frame (main street along x or z, randomly); rural roads
  are routed on an 8 m cost grid (AStarGrid2D) with settlements and water
  solid, woods expensive and a noise term for organic bends, then
  simplified (RDP that refuses shortcuts over solid ground) and Chaikin-
  smoothed. Existing roads are made expensive so new roads join instead
  of running alongside. Junctions are shared vertices (inserted into the
  target road), so the connectivity test is a plain union-find.
- **Build it all, bake near the player.** Instantiating the whole world
  costs ~1.1 s and ~27 k nodes, well under the 20 s budget, so every
  chunk is built (organised as chunk nodes for Round 12); navigation is
  per chunk and only near the player; zombies only near the start.
- **Cheap bulk geometry.** Per chunk: one MultiMesh of vertex-coloured
  unit boxes (fences, props, crop rows), trunk / canopy / pine
  MultiMeshes, one road mesh, one StaticBody with shape owners (no
  CollisionShape nodes) — the nav parser reads shape owners.
- **Tree fade by shader**, not by the OcclusionManager: MultiMesh
  canopies cannot fade per instance, so `tree_canopy.gdshader` dithers
  out canopies in a band between the camera and the player.

## Failed approaches / gotchas

- **Chunk regions returned wrong closest points.** Creating the 25
  NavigationRegion3Ds up front (empty) and assigning their meshes when the
  async bakes finished left every map query resolving to the last region
  (closest point to anywhere = a corner of chunk (9, 8)). The same meshes
  in freshly created regions work. Fix: create each region only when its
  mesh is baked (a re-bake swaps in a new region). Also waiting on
  `region_get_iteration_id` (4.5+ async region updates).
- **`border_size` warnings**: the border must be a whole number of cells
  in float32 — 1.95, 1.5, 1.8, 3.0 / 0.15 all "lose precision"; 1.2 and
  2.4 do not.
- **A* from inside a reserve**: roads leaving a settlement start inside
  the routing margin, so the start cell's neighbours were solid, A*
  failed and the fallback straight line cut through a farm. `_route` now
  opens the cells within 9 m of both ends, and path checks exempt only
  those 9 m.
- **Inner lot rows faced the wrong street** (the street is on the far
  side of rows backing onto the shops) — caught by the door-side check.
- **Farm walk paths crossed the farmhouse** — paths now run down the yard
  lane (the buildings stand either side of it).
- **Kitchens without windows** when the back door took their only
  exterior wall: back doors need 3.6 m of wall, doors sit near one end of
  a room's side, and a narrow-window fallback guarantees a window in
  living rooms, kitchens and bedrooms.
- **Loot tables** must follow the Round-9 global scarcity rule
  (`test_loot` checks every table): nails 3-12, nail boxes 10 %.
- **Static meshes leaked at exit** ("ObjectDB instances leaked") while the
  tree meshes were `static var`s on WorldBuilder; now instance vars.
- **Integration sharding** (first pass): the unstaged bot failed when
  shard order changed; fixed properly by seeding every component rng from
  the world seed and a deterministic cut, so the world test has its real
  weight.
- **Rotated door gaps closed in the navmesh** at 0.15 m cells / 0.3 m
  agent radius (a 0.9 m door at 7.5° rasterises shut): 0.1 m / 0.2 m.
- **Nav readiness under load**: `navigation_ready` could fire before the
  server had the regions (queries empty) → the verification step.
- **Headless frame timing**: wall time between frames is paced by the
  60 Hz physics clock; the walk probe sums the measured script work +
  region hand-over + light pass instead.
- **Small maps**: the 48 × 40 m farm yard rarely fits a 384 m map next to
  the town — both road sides, a relaxed pass and standalone yards with a
  routed drive fixed it; the stub of an L-shaped town could start on a
  dropped block (disconnected county road).

## Evidence

- `tests/output/37_world_map.png` (seeds 1337 / 7 / 99 side by side),
  `38_town_street.png`, `39_farmstead.png`, `40_woods_edge.png`,
  `41_town_overview.png` (zoom 44), `42_map_overlay.png` (M, real input),
  `43_town_night.png` (street lamps + lit windows).
- `scripts/test.sh unit`: 206 tests, 0 failed; integration a 42, b 70,
  c 59, d 75 tests, 0 failed (world scene 13 tests).
- `scripts/worldgen_sweep.sh 1 200`: 0 problems.
- `scripts/perf.sh`: all OK incl. `--world` (see Numbers).
- `SCREENSHOT_ONLY=world scripts/screenshots.sh` and the full run: OK
  twice.

## Gaps for Round 12

1. Stream chunk nodes in / out around the player (build radius, free far
   chunks, keep their changed statics as per-chunk records) and nav with
   them; save only changed statics.
2. Population sim over `chunk_density` (spawn / despawn zombies with the
   chunks, migration toward noise).
3. Building variety: real upper floors / stairs, L-shaped footprints,
   schools / police station.
4. Road polish: stop signs, raised kerbs, bridges.
5. Measure the night light budget on a real GPU.
