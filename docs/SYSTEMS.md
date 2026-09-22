# Systems

Status key: ✅ working & verified · 🔶 partial · ⬜ planned

## Movement & stamina ✅ (Round 1)

| Mode | Speed | Notes |
|------|-------|-------|
| Sneak | 1.3 m/s | Ctrl. Will reduce noise/visibility once zombies exist. |
| Walk | 2.0 m/s | Alt. |
| Jog | 3.4 m/s | Default. |
| Sprint | 5.6 m/s | Shift. Drains stamina 16/s. Not available when exhausted or standing still. |

- Stamina 100. Regen 9/s idle, 4/s moving. Exhausted at ≤2 % → speed ×0.75
  and sprint denied until ≥25 % (hysteresis prevents flicker).
- Speed modifiers are multiplicative and keyed by source, so encumbrance
  (R6), injuries (P3), terrain and status effects plug in without touching
  movement code.
- Interactions with other systems (planned): sprinting produces louder
  footsteps (R8); exhaustion will increase pain/stress and reduce melee
  effectiveness (R4/P3); hunger/thirst lower max stamina (R7).

## Camera ✅ (Round 1, dimetric in Round 2)

- Orthographic dimetric rig: 30° elevation, 8 headings (Q/R), 4 zoom
  levels as view sizes 10/14/20/28 (wheel, +/−), smooth follow. Perspective
  fallback kept (`orthographic = false`).
- Occlusion / cutaway: see below.

## Interaction framework ✅ (Round 2)

- Objects own their interactions: a body on layer 4 with an `Interactable`
  child returns a list of actions `{id, label, enabled, reason}` for an
  actor. Disabled actions stay listed with a reason (e.g. "Locked",
  "Window is closed") so the UI can explain.
- Player side (`PlayerInteraction`): best candidate within 1.6 m with line
  of sight, preferring what the character faces; E performs the first
  enabled action, 1-4 pick alternatives. Refusals ("Locked", "Blocked",
  "Busy"…) surface in the HUD notice. Events: `interaction_target_changed`,
  `interaction_performed`, `interaction_refused`.
- Planned consumers: containers/loot (R5-6), barricading (R8), vehicles,
  crafting stations. Zombies will use the same door API (R3).

## Doors & windows ✅ (Round 2)

| Object | States | Actions | Notes |
|--------|--------|---------|-------|
| Door | closed / open | Open, Close | Swings 90° away from the actor in 0.4 s; collision rotates with it. Refused "Blocked" when a character stands where the leaf would go; "Busy" for 0.5 s after a toggle; `locked` → "Locked". |
| Window | closed / open / smashed | Open, Close, Smash, Climb through | Full-height collision always; climbing (0.8 s, input locked, −12 stamina/s) is the only way through. Smash needs no tool yet. Smashed → "Climb through (glass)" and `hazard = true` in the result / `window_climbed` event (injury in R4). |

- Events `door_state_changed`, `window_state_changed` are the hooks for
  noise (R8) and zombie pathing (R3).
- Round 3: doors are **breakables** (group `breakable`, `take_damage()`,
  `blocks_path()`) with `health` 300. A zombie bangs 8 per 2 s (one
  zombie ≈ 75 s, four ≈ 20 s); every bang emits `door_banged(door,
  source)` plus a 10 m sound that recruits neighbours. At 0 the door is
  **broken**: leaf gone, doorway open forever, body kept on layer 4 only
  so "Close door (Door is broken)" stays readable. `door_state_changed
  (door, &"broken")`. Door leaves live on physics layer 7 so the navmesh
  bakes through doorways. Windows: sill + header are wall (layer 1); the
  glass is a child body on layer 8 (`window_panes`) while closed and on no
  layer once open / smashed — vision and interaction rays (1+7+8) see
  through open windows only. Open/close/hit/break/smash emit
  `sound_emitted` (see Sound events).

## Buildings ✅ (Round 2, blockout)

- A `BuildingPlan` resource (`data/buildings/house_a.tres`) describes
  footprint, rooms and walls with door/window openings; `HouseBlockout`
  generates all geometry at load (floor, 2.7 m walls 0.2 thick, lintels,
  doors, windows, flat roof, `Room` volumes). House A: 10×8 m, four rooms
  (bedroom, bathroom, kitchen, living room), front + back door, three
  interior doors, seven windows, placed at (−14, 0, −10).
- Rooms answer `contains_point`; `Building.locate()` finds the building /
  room for any point (used by occlusion, HUD; later by AI, loot spawning,
  save).

## Occlusion / cutaway ✅ (Round 2)

- Inside a building: roof hidden, camera-facing exterior walls (and doors
  / windows in them) cut to 0.35 m stubs, interior walls of the current
  room that would hide the player cut too; far walls stand (reference 4).
- Outside: anything on the occluder layer between the eye and the player
  (walls, roof, props) fades to 15 % alpha.
- 10 Hz, 0.2 s tweens, no thrash when idle. Collision never changes.

## HUD 🔶 (Round 1-2)

- Movement mode + stamina bar (green / orange <25 % / red exhausted, flashes
  on exhaustion), debug overlay (F3), key hints. Will grow per round; each
  system adds its own widget rather than the HUD knowing about systems.
- Round 2: bottom-centre interaction prompt ("E: Open door   [2] Smash
  window   [3] Climb through (Window is closed)"; greyed when nothing is
  enabled, hidden while busy), refusal reasons in the notice label, and an
  "Inside: <room> — <building>" line. All purely event-driven.
- Round 3: dark-red "♥ Health" bar (white text) above stamina; exhausted
  stamina is orange-red so the two never match; top-centre danger
  indicator "!  N chasing" (zombies in chase/attack on the player, from
  `zombie_state_changed` / `zombie_died`, pruned on `tree_exiting` and
  every frame so freed zombies never leave a stale count); red
  screen-edge flash on `character_damaged` (shader vignette, 0.55 s
  physics-time tween); "You died / Press R to restart" overlay on
  `character_died`.

## Zombies ✅ (Round 3, basic AI)

Data: `data/zombies/zombie_profile.gd` + `zombie_basic.tres`. Shamble
0.9 m/s, lunge/chase 1.6 m/s (a jogging human at 3.4 m/s always escapes;
an exhausted one at 2.0 m/s barely; a sneaker at 1.3 m/s is caught),
vision 14 m / 120°, memory 8 s, attack range 0.9 m, windup 0.5 s,
cooldown 1.5 s, damage 12, health 60, head hits ×3, door damage 20.

`Zombie` (CharacterBody3D, layer 3, group `zombie`) = `MovementComponent`
+ `StatsComponent` (health) + `ZombieSenses` + `ZombieAI` +
`ZombieVisual` (one shared 3-surface mesh: body / head / arms) +
`NavigationAgent3D`. Every number lives in the profile (no magic
constants in code).

### AI state machine (`zombies/zombie_ai.gd`, states in `zombies/states/`)

| State | What | Leaves when |
|-------|------|-------------|
| idle | stand 2–8 s | timer → wander; sight → chase; sound → investigate |
| wander | shamble to a random navmesh point ≤ 10 m from home (never inside a building) | arrived / 25 s / stuck / closed door ahead → idle |
| investigate | walk to a heard position (or last known) | within 1 m / 40 s / stuck → search; closed door ahead → attack_door |
| search | 4–6 s: turn to random headings, short shuffles | → wander |
| chase | 1.6 m/s to the last known position, re-path 2 Hz (seed-staggered); sight refreshes memory; at most `max_attackers` (4) bite one target, the rest **hold** at 1.4 m or once stuck in the crowd (ring, not blob) | in range + clear chest line + free slot → attack; memory 0 → lost_target; breakable ahead → attack_door |
| attack | windup 0.5 s (visual lunges 0.25 m) → hit if still in range, faced and with a clear line (`target.take_damage(12, zombie, {region: random})`, head flashes white) → cooldown 1.5 s | out of range → chase; target gone → lost_target |
| attack_door | same rhythm against `ai.blocking_obstacle` (`take_damage(8)` on any breakable) | it no longer blocks → chase or investigate |
| lost_target | transient: `zombie_lost_target`, forget | → search (near) / investigate (far) |
| stunned | 0.8 s freeze after a hit ≥ 20 damage (R4 combat hook) | → chase / idle |
| dead | corpse (see below) | — |

Unreachable targets: the path ends at the closest reachable point; the
zombie stands there facing the target and keeps re-trying at 2 Hz. No
biting through walls: entering Attack and every swing need a clear
chest-to-chest ray (layers 1+7+8). A zombie hit by something while it has
no target turns toward the attacker and investigates; a hit ≥ 20 stuns.
Head tint tells the state at a glance: normal / yellow (investigate,
search, attack_door) / red (chase, attack) / white flash (swing) / dark
(dead).

Death (`Zombie.die`): a `ZombieCorpse` (StaticBody3D, layer 4 only, group
`corpse`) takes over the collapsed visual where the body stood, with an
`Interactable` "Search corpse" disabled ("No inventory yet", R5);
`zombie_died(zombie, killer)` fires and the zombie node is freed.

### Senses (`zombies/zombie_senses.gd`)

- Vision at 6 Hz (0.5 s while chasing with the target in sight),
  staggered per zombie from its seed: distance ≤ range (sneaking target
  ×0.5, sprinting ×1.25) AND inside the 120° cone AND a clear ray from the
  zombie eye (1.5 m) to the target eye on layers 1+7+8 (walls, closed
  doors and closed window panes block; open / smashed windows do not).
  Pure `can_see()` is unit-tested.
- Proximity: anything within 1.5 m with a clear chest-to-chest line is
  noticed regardless of facing.
- Hearing: `sound_emitted` within radius × `hearing_sensitivity` →
  investigate that position (chasing zombies ignore sounds). A wall or
  closed door between ear and sound halves the radius
  (`hearing_wall_attenuation`).
- Round 3 prey is the player only (`GameManager.player`); dead players are
  ignored.

### Spawning (`zombies/zombie_spawner.gd`, node `Zombies` in the map)

10 zombies at map load (`count`, `seed` = 1337, repeatable) on random
navmesh points within 35 m, ≥ 15 m from the player, never inside or
within 1.5 m of a building room, never on prop tops. `spawn_at(position)`
for tests / the population sim. Each zombie gets a derived `ai_seed`.

### Performance

Per zombie: one `_physics_process`; senses 6 Hz (0.5 s while chasing in
sight), AI 20 Hz while hostile / 10 Hz otherwise, re-path 2 Hz — all
staggered from the zombie's seed (deterministic); standing zombies skip
movement entirely; calm zombies farther than `cheap_distance` (8 m) from
the player use "cheap" movement (MovementComponent velocity integrated
directly every other frame, body removed from the physics space — no
move_and_slide, no broadphase); surplus attackers hold instead of
pushing. Physics engine is Jolt. `scripts/perf.sh` (200 zombies, 600
frames, headless, measuring the scene-tree part of each physics step
with priority-bracketed probe nodes): **calm/loud ≈ 5 ms** (budget 8),
**hostile — all 200 chasing / holding / biting an invulnerable player —
≈ 8.5 ms** (budget 10) on the 2-core dev box (empty scene ≈ 0.2 ms).

## Sound events 🔶 (Round 3 stub, Round 8 fleshes out)

`EventBus.sound_emitted(position, radius, intensity, category, source)`.
Emitters: player footsteps at 1 Hz while moving (`FootstepEmitter`:
sneak 2 m, walk 4 m, jog 8 m, sprint 14 m), door open/close 6 m, door
bang 10 m (+ `door_banged`), door break 18 m, window open/close 5 m,
window smash 18 m. Listener side (`ZombieSenses`): radius test, halved
when a wall / closed door lies between ear and source (one ray). No real
propagation yet.

## Navigation ✅ (Round 3)

`NavigationRegion3D` + `world/nav_baker.gd` in the map: bakes at runtime
(thread) two physics frames after the house has generated, from static
colliders on layer 1 inside a 100×100 m box (`bake_aabb`); agent radius
0.3, height 1.5, cell 0.15 / 0.1 (project defaults match). Door leaves are
on layer 7, so doorways are walkable and zombies path into houses; a
closed door is handled by the AI (attack_door). Roofs (layer 6) and
characters are not baked. `navigation_ready` fires once the map is
queryable (~200 ms after load); the spawner waits for it. Windows are
walls for navigation (you climb, never walk).

## Health 🔶 (Round 3 minimal, Round 4 does injuries)

`HealthComponent` (child `Health` of the player, 100 HP from
`CharacterStatsProfile.health_max`): `take_damage(amount, source, info)`
→ local `damaged`/`died` + `character_damaged` / `character_died`.
`Character.take_damage()` delegates to it (duck-typed: zombies attack
anything with `take_damage`). On death the character is busy forever
(input ignored), the HUD shows "You died — Press R to restart" (`restart`
action reloads the scene) and zombies lose interest.

## Planned (see MASTER_PLAN for order)

Sound propagation ⬜ · Combat ⬜ · Health & injuries ⬜ · Inventory ⬜ ·
Loot tables ⬜ · Needs (hunger/thirst/fatigue/temperature) ⬜ ·
Barricades ⬜ · Save/load ⬜ · Crafting ⬜ · World time ⬜ · Vehicles ⬜ ·
Farming ⬜ · Weather ⬜ · Electricity ⬜ · Zombie population sim ⬜ ·
World streaming ⬜ · NPC survivors ⬜
