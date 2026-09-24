# Round 12 — builder notes (world streaming, zombie population sim, delta saves)

Brief sections: ZOMBIE POPULATION SIMULATION, WORLD STREAMING, PERSISTENT
WORLD, SAVE SYSTEM. Round 11 left "build the whole county at load, zombies
only near the start, save every static".

## What was built

- **Chunk recipes** (`worldgen/world_builder.gd`): the builder's
  `_build_*` passes now record per-chunk data instead of nodes — box /
  tree MultiMeshes and the road ArrayMesh as shared resources, solid
  shapes as `[shape, transform]`, buildings as layout records, lights /
  pumps / silos / ponds / canopy roofs / vehicles as `[kind, payload]`.
  `chunk_steps` / `build_chunk_step` instantiate a chunk in steps,
  `detach_chunk` / `free_chunk` remove it. Per-chunk impostor MultiMeshes
  (walls + roof-colour slab) stand in for unloaded buildings. Without a
  streamer every chunk is built as before (tools; the loot census is
  unchanged: food 142 on seed 1337).
- **`world/chunk_streamer.gd`** (`ChunkStreamer`, node `Streamer`): load
  ≤ 3 / unload > 4 chunks, sync ring 1 (never an unbuilt player chunk),
  4 ms build budget (a building always starts its own frame, the
  director's spawn time comes off the budget), nearest-first + walking
  direction priority, one unload and one node free per frame, capture /
  apply of saveables, items, corpses, blood.
- **`world/world_state_store.gd`** (`WorldStateStore`): delta store
  (build-time default vs unload-time state, `_t` + ageing for container
  food), per-chunk dynamic records, save round trip.
- **`simulation/`**: `ZombiePopulation` (pure: groups, wander / migrate /
  investigate, attractors, merge / split, hearing, compact save,
  deterministic), `PopulationDirector` (node `Population`: game-time
  ticks, loud-sound forwarding, nearest-first instantiation under a cap
  with a per-frame budget, folding back, deaths, distance LOD freeze),
  `PopulationParams` + `data/simulation/default_population.tres`.
- **Saves v2** (`SaveFile.VERSION` 2, `migrate_1_to_2`): streamed worlds
  save deltas + chunk records + population; hand-made maps unchanged;
  `WorldConfig.stream_state` carries the store / population / clock /
  player position into a fresh map before `_ready`; `SaveSchema` checks
  `chunks`, `population`, `_t`.
- **Debug**: F2 (`toggle_chunk_debug`) chunk / population layer on the M
  map (`WorldMapOverlay.set_debug`).
- **Tests**: `tests/unit/test_streaming.gd` (15), `tests/integration/
  test_world_streaming.gd` (10: unload / return restores container, door,
  window planks, item, corpse, blood; killed zombies stay dead; smash far
  away pulls a sim group that walks in as real zombies; conservation over
  a game day + fast-forward; untouched save < 50 KB; save / load after
  exploring; active cap + nearest first; spoilage in an unloaded chunk;
  Round-11 save migration; sprint across 5 borders with no frame > 33 ms),
  `test_world_scene.gd` updated (recipes vs loaded chunks, rural group via
  the population), `tests/integration/frame_timer.gd` (whole-frame
  intervals + per-frame notes for slow-frame reports),
  `tests/perf/perf_streaming.gd` (in `perf.sh --world`), screenshots
  44 / 45 (`SCREENSHOT_ONLY=streaming` runs Round 12 alone, `=world`
  Rounds 11 + 12). Integration now runs in five shards (`integration-a`
  … `-e`).

## Numbers (seed 1337, 2-core box, headless)

| | |
|---|---|
| Load (new game) | recipes 90 ms, 25 chunks sync + 24 over frames, nav 25 regions 3.5-4.8 s, total ≈ 5.4 s |
| Nodes | ~18.7 k near the start (49 chunks), ~9.5 k 400 m out in the country (R11: ~27 k always) |
| Chunk build | base ≤ 1.6 ms, building ~2 ms (≤ 9 ms first-of-a-kind), vehicle ≤ 3 ms |
| Memory | +23 MB on the first 1 km (caches: zombie looks, vehicle meshes, nav sources), +0-1 MB on the second km |
| Sprint 6.5 m/s | town: avg 6.9 / p99 11.7-13.9 / worst 18-27 ms; woods: p99 11 / worst 15-16 ms (after the critic fixes; 29-48 before); test route worst 15-17 ms |
| Population | 900 zombies / ~300 groups; 1000 zombies: tick 0.7 ms avg (p99 1.0); 8 game hours in one advance 15 ms |
| Saves | untouched 24 KB (40 ms); 50 changed objects 32 KB, save 45 ms, load 4.8 s |
| Tests | unit 223, integration 262 (5 shards 275-377 s), screenshots 46 OK |

## Decisions

- **Recipes, not a second builder.** The Round-11 build passes already
  sorted everything by chunk; recording their output (and committing the
  MultiMeshes / road meshes once) keeps one code path for streamed and
  non-streamed builds and makes a chunk load mostly "add nodes".
- **Defaults are recorded, not computed.** The store compares a saveable's
  state at unload with its own state right after the build (same seed →
  same object), so no system needed a "default state" API and unsearched
  containers stay unrolled for free.
- **Ownership by position at unload time** for items / corpses / blood:
  nothing tracks carrying or dragging; whatever lies in a chunk when it
  unloads belongs to it.
- **Members, not individuals, in the sim.** A zombie is an int in a
  group; its look is derived from the id; only wounds and foreign looks
  are stored. Saves compress member lists as ranges ("0-5,9").
- **Real zombies stay zombie records in saves** (with spawn ids
  `pop/<member>`), exact positions and calm states; data groups are the
  rest. Nothing is folded at save time.
- **Budgets everywhere a frame can spike**: 4 ms of chunk building,
  5 ms of zombie instantiation (shared), one unload and one node free per
  frame, navmesh parse one node per tick, merge + bake on a worker.
- **Distance LOD** for live zombies (frozen when calm and > 50 m) — the
  brief's "medium distance: simplified simulation"; without it 120 live
  zombies cost ~13 ms of physics scripts per step.
- **Calm path-query budget** (ZombieAI: ≤ 3 new calm paths per physics
  frame, hostile never delayed): a noise sent a whole group into the path
  finder on one frame. It helped some woods runs (49 → 29 ms worst) but
  not all (see KNOWN_ISSUES: 43-48 ms runs remain).

## Failed approaches / gotchas

- **`WorldNav.chunk_ready` every 0.25 s for 25 chunks** (closest-point
  queries) made every physics step ~15-20 ms slower — persistently, not
  just on the query frames. Cached per verified region now; found by
  disabling nodes one at a time (idle world: 22 ms → 5 ms physics).
- **`Building.room_at` for every listener × every building** every 0.2 s
  (SoundManager) — cheap with 1 house, 30-40 ms spikes with 120 zombies
  in town. Bounding-circle early-out.
- **`pick_spawn_point`'s 60 tries** when a member's spot was blocked:
  up to 50 ms per failed spawn; `find_spot` tries 5 and the group waits.
  Failed attempts count against the spawn budget (the list otherwise ran
  whole every frame).
- **Freeing a chunk in one go** (remove_child of thousands of nodes):
  20-70 ms. Detach first, free one building / vehicle / base per frame;
  a chunk reloaded before its old nodes are gone frees them first.
- **Parsing a town chunk's Solids body** for the navmesh: up to 12 ms;
  merging 3 × 3 sources on the main thread: 10-30 ms. Solid faces now come
  from the recipe on the worker, merge + bake too.
- **Two background bakes on a 2-core box** starved the main thread
  (buildings measured 7 ms instead of 2 ms meanwhile): one on ≤ 2 cores.
- **Adding nodes during the map's `_ready`** (a load restoring items in
  the first chunks) fails ("parent busy setting up children"): the
  streamer defers the dynamic restore to the end of the frame.
- **`Performance.TIME_PHYSICS_PROCESS`** refreshes once a second (the
  Round-8 note) — the streaming perf probe uses perf_zombies'
  PhysicsProbe; whole frames are timed with FrameTimer (headless has no
  vsync, so an interval is the frame's own cost).
- **A split group re-merged at once** (4 m offset < 6 m merge radius);
  splits now start 9 m apart, walking away.
- **SaveFile.migrations is cleared by a unit test's teardown**: the
  built-in 1 → 2 migration lives in `builtin_migration` (the table only
  overrides).

## Critic pass (11 items, fixed in place)

- **Perf root cause** (critic profiled it): every > 30 ms frame was zombie
  nav queries — tree trunks carved ~11 k polygons into the woods navmesh,
  and population zombies inherited goals 250-555 m away (off-mesh,
  unreachable → full searches). Trunks (< 0.45 m) are no longer carved;
  far goals are walked in 40 m legs; spawned zombies clamp the group goal
  into the loaded chunks; agents search ≤ 60 m (which also removed the
  engine "most reachable polygons" error). Woods sprint worst 48 → 15 ms;
  perf bounds restored (33 ms worst, load 8 s); one building of each kind
  is built at load; a building step waits a frame (≤ 2) after the
  director worked. Nav-query guard: `ZombieAI.path_queries /
  far_queries / unreached_queries` (woods sprint: 112 queries, 0 far, 0
  unreached).
- **Bugs**: cheap movers slid through closed doors into sealed houses
  (now hand over to full physics at a building boundary);
  `random_nav_point` returned an indoor point; unloading a half-built
  chunk erased its stored items; a zombie killed in the frame it was
  folded came back; tests mutated the shared population .tres; the
  conservation test now spawns, folds and kills over its game day.
- **Gameplay**: per-category `sim_carry` (sprint footsteps no longer
  "loud"), indoor halving, zombies-follow-zombies relays through live and
  data zombies, town car alarms on break-in. A main-street window smash
  turned 8 data groups 100-200 m away (the first live ~10 game minutes
  later at shamble speed — 0.9 m per game minute = the live shamble at
  1×); a car alarm turns every group within 315 m.
- New tests: `tests/integration/test_world_population.gd` (6),
  2 unit tests (relays, which sounds the sim hears).

## Evidence

- `tests/output/44_chunk_debug.png` (M + F2 by real input after walking
  250 m: loaded 7 × 7 framed, per-chunk counts, groups, live zombies),
  `45_horde_arriving.png` (a 120 m car alarm: 86 simulated zombies turned,
  28 instantiated at the active edge, 37 walking in).
- `scripts/test.sh unit`: 221 / 0 failed; integration a 49, b 35,
  c 47, d 65, e 60 — 0 failed.
- `scripts/perf.sh --world` (see Numbers; perf_world unchanged OK).
- `SCREENSHOT_ONLY=world scripts/screenshots.sh` and the full run: OK.

## Gaps for Round 13

1. Path-query budget for hostile zombies too / cheaper woods navmesh
   (coarser cells outside settlements).
2. Horde markers on the map once seen; sim groups that avoid water /
   buildings; migration toward noise-rich areas (player's base).
3. Re-bake a chunk's navmesh when a neighbour's content arrives after it.
4. Crops / generators as chunk state that advances lazily with time.
