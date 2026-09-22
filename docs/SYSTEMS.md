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
- Round 4: top-right body panel — "Weapon: Baseball Bat  (11/12)" +
  condition bar, "Pain N%", green "INFECTED", injury list ("• Left leg —
  Laceration  BLEEDING" / "(bandaged)"); "Aiming — N in reach";
  refusal / pickup / bandaging / broken-weapon notices; charge meter
  while charging, bandage progress bar; "Stamina 60 %" + " · max 80 %"
  only when wounds lower the cap; mode "Idle" when standing; health bar
  follows `health_changed` (bleeding); key hints on a dark strip.
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
| stunned | 0.8 s freeze after a hit ≥ 10 damage (0.6 s after a shove) | → chase / idle |
| knocked_down | on the ground 2.5 s (weapon knockdown roll or shove); no attacks; damage ×1.5; visual lies on its back | → chase / idle |
| dead | corpse (see below) | — |

Unreachable targets: the path ends at the closest reachable point; the
zombie stands there facing the target and keeps re-trying at 2 Hz. No
biting through walls: entering Attack and every swing need a clear
chest-to-chest ray (layers 1+7+8). A zombie hit by a creature (anything
with `take_damage` that is not a zombie) makes it its target and chases;
hit by anything else while it has no target it turns and investigates; a
hit ≥ 10 stuns, a knockdown floors it (Round 4, see Melee combat). Bites
roll a body region + wound type on the victim (`roll_attack_info()`).
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
window smash 18 m, melee hit = weapon noise radius (bat 8 m, knife 2 m,
shove 2 m). Listener side (`ZombieSenses`): radius test, halved
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

## Melee combat ✅ (Round 4)

`MeleeCombat` (combat/melee_combat.gd, child `Combat` of the player; generic
for NPCs; a facade over `SwingStateMachine` (timing / queue) and
`HitResolver` (targets, damage, wear, events)) + `PlayerCombatInput`
(player/) + `MeleeVisuals` (combat/). Shared tuning in
`data/combat/combat_profile.tres` (`CombatProfile`: charge curve, stamina
multipliers, movement slows, hit height 1.1 m, target radius, regions,
noise scaling).
Weapons are data: `WeaponData extends ItemData` in
`data/items/weapons/*.tres`.

| Weapon | Dmg | Reach | Arc | Targets | Swing | Stamina | Knockback | Knockdown | Crit | Condition |
|---|---|---|---|---|---|---|---|---|---|---|
| Fists | 3–5 | 0.8 | 60° | 1 | 0.5 s | 2 | 0.25 | 5 % | 5 % ×2 | — |
| Baseball bat | 12–18 | 1.4 | 120° | 2 | 1.1 s | 12 | 0.3 | 15 % | 10 % ×2 (head 12 %) | 12 (20 %/hit) |
| Kitchen knife | 5–8 | 0.9 | 40° | 1 | 0.4 s | 3 | 0.05 | 0 (never staggers) | 35 % ×3 | 10 (25 %) |
| Crowbar | 10–15 | 1.2 | 70° | 2 | 0.75 s | 7 | 0.25 | 10 % | 10 % ×2 | 30 (8 %) |
| Hammer | 8–12 | 0.95 | 60° | 1 | 0.55 s | 5 | 0.2 | 8 % | 15 % ×2.5 | 20 (10 %) |
| Lead pipe | 9–14 | 1.2 | 90° | 2 | 0.7 s | 7 | 0.25 | 12 % | 10 % ×2 | 20 (12 %) |
| Shove (Space) | 0 | 1.0 | 90° | 3 | 0.45 s | 5 | 1.2 | 25 % (50 % vs windup) | — | — |

- **Swing**: LMB press starts charging (speed ×0.7), release swings with
  ×0.6 (tap) → ×1.3 (held 1 s). Stamina is paid at the swing start; not
  enough → refused, `attack_refused(actor, "Too tired to swing")` → HUD
  notice. Windup (35 % of the swing, speed ×0.4) → active window (20 %,
  the arc is shown, targets resolved once) → recovery. Pressing during a
  swing queues the next one (held through recovery → keeps charging);
  any interrupted swing (busy — climbing / bandaging —, death) drops the
  queue. X is refused mid-swing ("Mid-swing"); wear always lands on the
  instance that was swung.
- **Pain** (thresholds in the injury profile): > 50 → damage ×0.85, swing
  time ×1.15; > 80 → ×0.7 / ×1.3.
- **Targets**: sphere query (reach + 0.3 m body radius) on layer 3 →
  pure `select_targets()` (flat distance, angle ≤ half arc widened by the
  body's angular radius, closest first) → LOS ray at 1.1 m on 1+7+8 (no
  hits through walls / closed door leaves / closed panes; open windows
  are fine, the ray clears the sill) → capped at max_targets.
- **Per target**: rand(min,max) × charge × stamina (exhausted ×0.6, low
  ×0.85); crit roll; head-hit roll (zombie head ×3); knockback along the
  attacker→target line; knockdown roll → `take_damage(dmg, actor,
  {region, knockback_dir, knockback, knockdown, crit, weapon, charge})`.
  A connecting swing emits a `melee` sound (weapon noise radius: bat 8 m,
  knife 2 m) and rolls condition loss; 0 → `weapon_broken`, back to fists.
- **Shove**: same pipeline, no damage; `receive_shove()` cancels a
  windup, knocks back 1.2 m, knocks down (25 %, 50 % vs a zombie winding
  up) or staggers 0.6 s.
- **Aim** (RMB): mouse → ground via `Camera3D.project_ray_origin/normal` +
  plane (works with the orthographic camera), body faces the aim
  (`Character.facing_override`), mode capped at walk, ring at reach (orange
  when something is in reach) + faint arc preview, HUD "Aiming — N in
  reach" (10 Hz).
- **Zombie side** (all numbers in `ZombieProfile`): stun 0.5 s on hits ≥
  16 (weapons with `can_stagger = false` — the knife — never stun), no
  new stagger within 1.2 s of the last (no stun-lock; a shove during the
  immunity still cancels the windup), knocked down 2.5 s ×1.5 damage
  (the knockback of the floor-ing blow still slides it), knockback at
  5 m/s with collision, body + head hit flash 0.2 s then back to the state
  tint, a creature that hits a zombie becomes its target. Bite: range
  1.0 m, windup 0.4 s.
- Events: `melee_swing`, `melee_hit`, `attack_refused`,
  `melee_aim_changed`, `weapon_equipped`, `weapon_condition_changed`,
  `weapon_broken`, `zombie_knocked_down`, `zombie_got_up`.
- Balance (tests, the critic's bot: stands still, aims at the nearest,
  0.35 s charge, shoves windups; seeds 1–5): bat vs 1 zombie costs
  12–27 % (avg 23 %, band 5–35 %); bat vs 3 zombies kills the bot in all
  5 seeds (band: > 50 % or death); 4 zombies kill a passive player in
  ≈ 5 s (< 30 s).

## Injuries ✅ (Round 4)

`InjuryComponent` (injuries/, child `Injuries` of the player) + `Injury`
(RefCounted) + `InjuryProfile` / `InjuryTypeSpec` data
(`data/injuries/human_injuries.tres`).

- 10 regions: head, neck, upper/lower torso, left/right arm, left/right
  hand, left/right leg. 6 types:

| Type | Bleed hp/s | Stops by itself | Pain | Heal | Infection (zombie) | Leg slow | −Max stamina |
|---|---|---|---|---|---|---|---|
| Scratch | 0.04 | 45 s | 8 | 5 min | 7 % | ×0.95 | 2 |
| Laceration | 0.12 | 120 s | 18 | 15 min | 25 % | ×0.8 | 5 |
| Deep wound | 0.3 | never | 30 | 30 min | 25 % | ×0.65 | 10 |
| Bite | 0.2 | 180 s | 25 | 20 min | 100 % | ×0.75 | 8 |
| Burn | — | — | 35 | 40 min | — | ×0.85 | 10 |
| Fracture | — | — | 45 | 100 min | — | ×0.5 | 15 |

- Any hit whose info has a `type` becomes a wound on `info.region`
  (`random` → profile weights). Zombie bites roll region
  (`ZombieProfile.attack_region_weights`: arms/torso/neck heavy) and type
  (scratch 60 / laceration 28 / bite 12 %) with `infectious = true`.
  Smashed-window climbs lacerate a hand/arm/leg (4 damage).
- Effects, recomputed on change: bleeding drains health via
  `HealthComponent.drain()` (no flash, no new wound) at 10 Hz and drips
  blood; leg wounds set the movement modifier `injury` (product, floor
  ×0.4; bandaged wounds slow half as much); open wounds lower max stamina
  (cap −40); `pain` stat = capped sum (bandaged ×0.6); an infected wound
  makes the `infection` stat rise 0.02 %/s (≈ 83 min to 100 %), after
  which health drains 0.5/s.
- **B** bandages the worst wound (fastest bleeder, else most painful):
  4 s busy (the Character owns the tween; no movement, no swings) →
  bleeding stops, heals ×2. Only bleeding wounds qualify, by
  `bandage_priority` (deep wound > bite > laceration > scratch); fractures
  and burns never ("Nothing to bandage"). Taking damage interrupts it
  (`bandage_interrupted`, HUD "Interrupted"). HUD progress bar.
- Infection is invisible until the stat reaches 25 → "Feverish"
  (orange), ≥ 60 → "Infected" (red) (`infection_stage_changed`).
- Events: `injuries_changed(character, summary)`, `bandage_started`,
  `bandage_finished`, `blood_spilled`, `health_changed`.

## Items (Round 4 minimal) 🔶

`ItemData` (id, name, category, weight, max_stack, max_condition, colour,
world size) → `ItemInstance` (condition, stack, to/from dict).
`WorldItem` (StaticBody3D, layer 4, group `world_item`) offers "Pick up
<name>" → `actor.pick_up_item(item)`. The map has a baseball bat in the
living room and a kitchen knife in the kitchen. `Player.held_items` is a
stopgap list until the Round-6 inventory; X cycles fists → held weapons;
picking a weapon up with empty hands equips it.

## Blood decals (Round 4)

`BloodDecals` (effects/, node in the map): one `MultiMeshInstance3D` of
200 flat discs, ring-buffer reuse (oldest first). Splats on `melee_hit`,
`character_damaged` and bleeding drips.

## Health 🔶 (Round 3 minimal, Round 4 injuries on top)

`HealthComponent` (child `Health` of the player, 100 HP from
`CharacterStatsProfile.health_max`): `take_damage(amount, source, info)`
→ local `damaged`/`died` + `character_damaged` / `character_died`.
`Character.take_damage()` delegates to it (duck-typed: zombies attack
anything with `take_damage`). On death the character is busy forever
(input ignored), the HUD shows "You died — Press R to restart" (`restart`
action reloads the scene) and zombies lose interest.

## Planned (see MASTER_PLAN for order)

Sound propagation ⬜ · Combat ✅ (melee) · Health & injuries ✅ · Inventory ⬜ ·
Loot tables ⬜ · Needs (hunger/thirst/fatigue/temperature) ⬜ ·
Barricades ⬜ · Save/load ⬜ · Crafting ⬜ · World time ⬜ · Vehicles ⬜ ·
Farming ⬜ · Weather ⬜ · Electricity ⬜ · Zombie population sim ⬜ ·
World streaming ⬜ · NPC survivors ⬜
