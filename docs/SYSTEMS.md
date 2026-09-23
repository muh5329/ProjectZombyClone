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
  effectiveness (R4/P3). R7: hunger / thirst / sickness lower max
  stamina, fatigue slows stamina regen (see Survival needs); resting on a
  bed / sofa triples idle regen.

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
  source)` plus a 12 m `door_bang` sound that recruits neighbours. At 0 the door is
  **broken**: leaf gone, doorway open forever, body kept on layer 4 only
  so "Close door (Door is broken)" stays readable. `door_state_changed
  (door, &"broken")`. Door leaves live on physics layer 7 so the navmesh
  bakes through doorways. Windows: sill + header are wall (layer 1); the
  glass is a child body on layer 8 (`window_panes`) while closed and on no
  layer once open / smashed — vision and interaction rays (1+7+8) see
  through open windows only. Open/close/bang/break/smash make
  SoundManager sounds (see Sound propagation); smashing leaves broken
  glass (Round 8, below).

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
- Round 8: "Noise" meter under the stamina bar (last player noise
  radius, LOUD past 10 m), "You shout!" / "Stepped on broken glass!"
  notices, busy label "Clearing glass", hint line gains H shout / F4.
- Round 3: dark-red "♥ Health" bar (white text) above stamina; exhausted
  stamina is orange-red so the two never match; top-centre danger
  indicator "!  N chasing" (zombies in chase/attack on the player, from
  `zombie_state_changed` / `zombie_died`, pruned on `tree_exiting` and
  every frame so freed zombies never leave a stale count); red
  screen-edge flash on `character_damaged` (shader vignette, 0.55 s
  physics-time tween); "You died / Press R to restart" overlay on
  `character_died`.

- Round 6: "Carrying W / 8 kg — <state>" readout (state colour) + state
  notices, "Too heavy" sprint refusal, "Dropped …", "Wearing …",
  bottom-centre hotbar (3 slots). Layout: notices moved below the
  player (y 428) with an outline so they never sit under the inventory
  panels; the key-hint strip is a bottom-right block; prompt / aim /
  charge moved up above the hotbar.
- Round 7: top-right `ClockWidget` (ref 4: cyan "08:10", "71.6°F 07/12",
  speed steps `|| > >> >>>` with the current one lit), `MoodleList`
  under it (one row per need above fine: "Hungry" + a severity-coloured
  circle with the need's initial, tooltip "Hunger: level 2 / 4"); the
  body panel is pushed below the moodles. Notices for need levels ≥ 2
  ("You feel hungry"), eating ("Ate Canned Beans — it was rotten!"),
  speed changes ("Fast forward ×4", "Paused"), sleep / rest
  ("Resting on the sofa… (move to get up)", "Woken by noise!", "You
  wake up rested"). Sleep fades the screen to near-black with
  "Sleeping…  02:13". Hint strip: "F5-F8 time speed".
- Round 5: generic timed-action bar + label (`timed_action_started /
  finished`: "Rummaging in kitchen cabinet…"), "Wound on … reopened!",
  "No bandages", hint "Tab inventory". The loot window is its own
  CanvasLayer (`ui/inventory/`).

## Zombies ✅ (Round 3, basic AI)

Data: `data/zombies/zombie_profile.gd` + `zombie_basic.tres`. Shamble
0.9 m/s, lunge/chase 1.6 m/s (a jogging human at 3.4 m/s always escapes;
an exhausted one at 2.0 m/s barely; a sneaker at 1.3 m/s is caught),
vision 14 m / 120°, memory 8 s, attack range 0.9 m, windup 0.5 s,
cooldown 1.5 s, damage 12, health 60, head hits ×3, door damage 20.

`Zombie` (CharacterBody3D, layer 3, group `zombie`) = `MovementComponent`
+ `StatsComponent` (health) + `ZombieSenses` + `ZombieAI` +
`ZombieVisual` (Round 8.5: a procedural `CharacterModel` — a former
townsperson, see "Character models & animation") + `NavigationAgent3D`. Every number lives in the profile (no magic
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
The eyes tell the state (Round 8.5, subtle like PZ): dark sockets when
calm / dim yellow glow (investigate, search, attack_door) / red glow
(chase, attack) / white flash (bite) / dark (dead); the readable tell is
the body language — hunched shamble, arms-out chase, the z_attack lunge.

Death (`Zombie.die`): a `ZombieCorpse` (StaticBody3D, layer 4 only, group
`corpse`) takes over the visual where the body stood (the model falls
face down with `z_death`, or stays on its back if it was knocked down,
and keeps that pose); since
Round 5 it is a `LootContainer` ("Search corpse", zombie_corpse table);
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
- Hearing (Round 8): the senses node is a SoundManager listener; see
  "Sound propagation / zombie hearing" below. The Round-3 "halved
  through walls" rule is gone.
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
Round 8.5 (with the animated models, this box): calm 3.8–4.1 ms (was
3.2), hostile 7.1–7.5 ms (was 5.9), noisy 3.8–3.9 (3.1), horde 1.3–1.7
(1.1); p99 ≤ 12 ms; idle-frame process time ≈ 0.8–1.4 ms (printed, not
budgeted).

## Sound propagation / zombie hearing ✅ (Round 8)

Gameplay sounds (not audio playback) go through the `SoundManager`
autoload: `emit_sound(category, position, source, overrides)`. Every
event also fires `EventBus.sound_emitted` (HUD, sleep, debug).

**Categories** (`data/audio/sound_categories.tres`, radius m / intensity):

| Category | Radius | Int. | Emitter |
|---|---|---|---|
| footstep_sneak / walk / jog / sprint | 2 / 4 / 8 / 14 (× encumbrance 1.2 / 1.35) | 0.1–0.6 | FootstepEmitter, 1 Hz while moving |
| door_open / door_close | 6 / 8 | 0.3 / 0.4 | Door (source = the actor) |
| door_bang / door_break | 12 / 18 | 0.7 / 1.0 | Door.take_damage (zombies) |
| window_open / window_close | 5 | 0.3 | HouseWindow |
| window_smash | 20 | 1.0 | HouseWindow.smash(actor) — the loudest player noise so far |
| melee_swing | 4 | 0.2 | every weapon swing (not shoves) |
| melee_hit / shove | weapon `noise_radius` (bat 8, knife 2, fists 3) / 5 | radius / 14 | HitResolver, on connect |
| rummage | 3 (container `search_noise_radius`) | 0.2 | ContainerAccess.search |
| eat / bottle_fill | 1.5 / 4 | 0.1 / 0.2 | ConsumeAction |
| shout | 20 | 0.9 | player H (ShoutComponent: 6 stamina, 3 s cooldown) |
| glass_clear | 3 | 0.2 | "Remove broken glass" |
| zombie_moan | 6 | 0.25 | investigating zombies, 10 s cooldown |
| alarm / gunshot / generator / vehicle | 60 / 60 / 25 / 30 | — | future |

**Propagation** (per listener within radius × sensitivity × masking):
- Direct: an iterative ray sound (1.2 m up) → ear (zombie eye 1.5 m) on
  layers 1+7+8 with `hit_from_inside`, re-cast past each hit body (≤ 5
  obstacles). EVERY obstacle multiplies: wall ×0.5, closed door ×0.6,
  closed window ×0.7, other solids (furniture, props) ×0.85 — a prop
  never hides the wall behind it; product ≥ 0.15. Cached per event by
  the ear's 1.5 m cell.
- Door / window sounds start 0.3 m off the opening on the actor's side
  (outward without one), so the leaf muffles them for the far side; a
  door's close sound comes when the swing ends.
- Through openings (open exterior doors / open or smashed windows):
  sound in building A, ear outdoors on the outward side of an A opening;
  sound outdoors on the outward side of an opening of the ear's building
  B; or A → B through one opening of each (the leg between them assumed
  clear). slack = radius × Π leg attenuations − Σ leg lengths; the best
  path wins (`path` = `direct` / `opening`). Ear buildings are cached
  per listener at 5 Hz.
- `emit_sound` rejects non-finite positions / radii (warning, no event);
  `queue_sound` spreads bursts (zombie moans) over frames, ≤ 2 per frame.
- Heard when slack ≥ 0; strength = intensity × slack / (radius ×
  sensitivity × masking). `SoundManager.ambient_masking` (1.0) is the
  weather / rain hook.
- Dispatch is O(listeners near): a SpatialHash (8 m cells) of listener
  ears refreshed at 5 Hz; dead / freed zombies unregister (death,
  `_exit_tree`, and a prune on dispatch).

**Zombie reactions** (`ZombieProfile`): idle / wander / search /
investigate zombies react; chasing ones ignore sounds.
- strength ≥ `loud_sound_strength` (0.4) → investigate at chase speed
  (1.6 m/s); fainter → turn toward it, stand `faint_turn_seconds` (0.8),
  then shamble (0.9 m/s).
- Priority: an investigating zombie switches only to a sound at least as
  strong as its current one minus `sound_priority_decay` (0.05/s) × age;
  a re-target never downgrades (loud stays loud, hop count keeps the
  minimum, strength the maximum).
- Lures: after investigating a `lure_search_categories` sound (the
  player's shout) the search lasts 8–12 s and its shuffles widen by up
  to 4 m.
- Hordes: investigating zombies moan (`zombie_moan`, 6 m) every
  `moan_cooldown` (10 s); a zombie that hears a moan heads for the
  moaner's own goal (`lure`), relayed at most `moan_max_hops` (2) times.
- Examples (tests): sneaking 4 m behind an idle zombie is not heard,
  sprinting is; a shout lures a zombie 18 m away; a window smash is heard
  15 m in front of the window but not 15 m away behind two walls; a bang
  inside with the front door open reaches 11 m in line with the door but
  not 6.6 m behind the wall.

**Player feedback**: `NoiseRings` (map node) — a ground ring per
player-caused sound that expands to the radius and fades in 1.1 s
(orange at ≥ `SoundCategoryTable.player_loud_radius`, 10 m — the same
number as the meter; pool of 20); HUD "Noise" meter under stamina (last
player noise radius on a 0–20 m bar, tick + "LOUD" at 10 m, holds
0.8 s, drains 8 m/s); "You shout!" notice. A dead player gets no
rings, meter or shout notice. **F4** (`toggle_sound_debug`) →
`SoundDebugOverlay`: every live event as a circle (orange = player,
cyan = others) + a line from each zombie that heard it (green direct,
yellow via an opening) labelled with its perceived strength; no work
at all while off.

**Sleep** (Round 8): the sleeper is a SoundManager listener; a sound
whose propagated strength at the ear reaches
`NeedsProfile.wake_sound_strength` (0.1) wakes, as does a zombie within
10 m WITH line of sight (no more waking through walls).

**Broken glass** (`GlassShards`, a sibling of the smashed window so the
cutaway never fades it): 1.2 m out on both sides of the wall (1.2 ×
2.4 m, 40 bright shards); walking (not sneaking, not busy) without shoes
(`Player.has_foot_protection()`: an equipped item tagged `shoes` — none
exist yet) → leg scratch at 25 %/s (1 − 0.75^dt per tick, ≥ 1.5 s
apart), `EventBus.hazard_hurt`, notice "Stepped on broken glass!".
Climbing through while glass remains: 40 % laceration
(`InjuryProfile.glass_laceration_chance`). Window action "Remove broken
glass" (3 s busy `clear_glass`, 3 m `glass_clear` noise, HUD "Clearing
glass") frees it and makes climbing safe. Smashed windows no longer
list the permanently disabled Open / Close entries.

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
  bleeding stops, heals ×2. Round 5: it **consumes** the best dressing in
  the inventory (bandage before rag; "No bandages" otherwise; returned
  if interrupted). A rag (quality 0.5) heals slower (×1.5) and has a 50 %
  chance that the wound bleeds again after 60 s (`wound_reopened`, HUD
  notice). Only bleeding wounds qualify, by
  `bandage_priority` (deep wound > bite > laceration > scratch); fractures
  and burns never ("Nothing to bandage"). Taking damage interrupts it
  (`bandage_interrupted`, HUD "Interrupted"). HUD progress bar.
- Infection is invisible until the stat reaches 25 → "Feverish"
  (orange), ≥ 60 → "Infected" (red) (`infection_stage_changed`).
- Events: `injuries_changed(character, summary)`, `bandage_started`,
  `bandage_finished`, `blood_spilled`, `health_changed`.

## Items ✅ (Round 4 weapons, Round 5 catalogue)

41 `ItemData` resources under `data/items/<category>/` (39 lootable +
fists / shove tagged `internal`), indexed by the `ItemDB` autoload
(recursive scan, unique ids enforced with `push_error`). Every item has
an enum category (food, drink, medical, weapon, tool, material,
clothing, container, misc), tags, a description, weight, max stack and
a blockout colour (also its UI icon).

| Category | Items |
|---|---|
| Food (`FoodData`: kcal, hunger, thirst, spoil days, needs opener) | canned beans, chips, bread, apple, peanut butter, cereal, candy bar |
| Drink | water bottle, soda, milk, orange juice |
| Medical (`MedicalData`) | bandage (quality 1), rag (0.5, 50 % rebleed after 60 s), disinfectant, painkillers, splint |
| Weapon (`WeaponData`, R4) | baseball bat, crowbar, kitchen knife, hammer, lead pipe |
| Tool | screwdriver, saw, tin opener, wrench |
| Material | nails (stack 100), box of nails, plank, duct tape, bed sheet |
| Clothing | t-shirt, jacket, socks (data only, worn in R6) |
| Container (`ContainerItemData`: `capacity_kg`, `weight_reduction`, `worn_speed_multiplier`) | school bag (0.7 kg, 7 kg, contents count 70 %), duffel bag (1.8 kg, 18 kg, contents count 60 %, ×0.97 speed while worn) — worn on the back (R6) |
| Misc | lighter, newspaper, matches, small change (stack 100) |

Food / drink numbers are consumed by the needs system in Round 7.

## Inventory ✅ (Round 5 model, Round 6 equipment / bags / encumbrance)

`ItemContainer` (pure data): weight capacity, stacks merge by id up to
`max_stack` (items with a condition never stack), `split_stack`,
`transfer_to` moves as much as fits ("Too heavy" when nothing fits),
`to_dict/from_dict`. The player's **main inventory** is a hard 20 kg
(`CharacterStatsProfile.inventory_capacity`); bags add their own
capacity; **encumbrance** (below) is what hurts, not the hard cap.

**Nested containers.** Every `ItemInstance` of a `ContainerItemData`
owns an `ItemContainer` (`contents`, `capacity_kg`). A bag weighs its
contents (`unit_weight` / `total_weight`), so capacity checks see a full
bag as heavy. Rules (`ItemContainer.accept_reason`): a bag never ends
up inside itself at any depth ("Can't put a bag inside itself"); a worn
bag never goes into another bag ("Take the bag off first"). Only the
worn bag's contents and a bag lying on the ground are accessible (a bag
inside the main inventory is a closed, full-weight item) — this keeps
every container's capacity invariant. `to_dict` nests `contents`.

**Picking up**: into the main inventory; when that is full, a weapon /
tool goes straight into empty hands and a bag onto an empty back.
A weapon is auto-equipped when the hands are empty.

## Equipment ✅ (Round 6)

`Equipment` (inventory/equipment.gd, child of the Player). Slots are
unlimited ItemContainers tagged with their slot id, so equipped items
are **out of the inventory** and every generic transfer works on them.

| Slot | Holds | Notes |
|---|---|---|
| primary_hand | weapons, tools, `&"hand"`-tagged items | MeleeCombat swings it. **Two-handed** weapons (`WeaponData.two_handed`: baseball bat) occupy both hands. |
| secondary_hand | one-handed items | Equipping here displaces a two-hander. |
| back | bags only ("Only bags go on the back"; "Bags go on the back" for hands) | Its contents are carried storage with the bag's weight reduction; the loot window gets a tab for it. |
| hotbar 1-3 | `Hotbar` (inventory/hotbar.gd): references to equippable items | Keys **1-3** (with any modifier held: sprint / sneak / walk) equip / put away. A dropped / stored item keeps its slot (greyed, "Not carried") and works again once that same item is picked back up. |

- Equip takes one item of a stack; whatever is in the way goes to the
  main inventory, else the worn bag — or the whole equip is refused
  ("No room in inventory"; the new item's weight leaving the pack is
  counted first). Unequip → main inventory, else worn bag, else refused.
- `Player.can_release_item` guards everything leaving a slot (the
  swung weapon: "Mid-swing").
- **X** cycles fists → every carried weapon (hands, pack, bag) in
  creation order (`ItemInstance.uid`) → fists.
- A broken weapon is destroyed from its slot (`on_weapon_broken`).
- Events: local `equipped_changed(slot, item)` (MeleeCombat mirrors the
  primary hand, MeleeVisuals rebuilds), `EventBus.equipment_changed`,
  `EventBus.hotbar_changed`. `to_dict/from_dict` (bags with nested
  contents; hotbar as references into slots / main / bag);
  `Player.carried_to_dict/carried_from_dict` wraps inventory + equipment.

**Keys:** 1-3 hotbar (any modifiers — Shift / Ctrl / Alt are sprint /
sneak / walk and may be held). **Interaction alternatives are on keys
4-7** (the prompt reads "[5] Smash window"): number keys 1-3 are always
the hotbar, so pressing 1 next to a door in a fight draws a weapon.
Taking off the worn bag with no room for it drops it at the feet
("No room: dropped School Bag at your feet"). `from_dict` goes through
the same slot rules (a two-hander only in the primary hand; a one-hander
next to a two-hander or a bag in a hand is rejected with a warning).
Save entries use one key, `count` (the old `stack` is still read).

## Encumbrance ✅ (Round 6)

`Encumbrance` (inventory/encumbrance.gd, child of the Player).
Carried weight = main inventory (a bag inside counts in full) + hand
items + worn bag weight + its contents × (1 − `weight_reduction`).
Thresholds and effects live in `CharacterStatsProfile` ("Carrying";
strength-based later):

| State | Carried | Speed (`encumbrance` modifier) | Stamina drain | Footsteps | Sprint |
|---|---|---|---|---|---|
| ok | ≤ 8 kg (`carry_capacity`) | ×1 | ×1 | ×1 | yes |
| light | 8 – 12 kg | ×0.92 | ×1.15 | ×1 | yes |
| heavy | 12 – 15 kg | ×0.85 | ×1.3 | ×1.2 | yes |
| overloaded | > 15 kg | ×0.65 | ×1.7 | ×1.35 | refused "Too heavy" |

Effects go through existing hooks only: `MovementComponent` modifier,
`StatsComponent.set_drain_multiplier` (scales negative rates only —
regeneration is untouched), `FootstepEmitter.set_multiplier`,
`Character.set_sprint_lock` (+ `sprint_denied_reason()`; the HUD shows
it); a worn duffel adds the `worn_bag` modifier ×0.97. Recompute is
**coalesced**: container changes mark it dirty, one recompute runs at
the end of the frame (reading `state` / `weight` flushes early), and
`EventBus.encumbrance_changed(character, state, weight)` fires only when
the final weight or state differs — equipping from the pack at 15.7 kg
never flickers through "heavy". Nested bags anywhere (in the pack, in a
bag in the pack) re-emit their container's `changed`, so the weight is
always current; container weights are cached and updated incrementally. HUD: "Carrying 12.4 / 8 kg — Heavy load" in the status panel,
coloured (grey / yellow / orange / red), plus a notice on state change.
The inventory screen shows the same **load** ("Carrying 6.9 / 8 kg")
under its tabs; its panel headers show **storage** as "Space 4.70 / 20
kg" — two different numbers, labelled differently. The worn bag's row
shows "School Bag 1.4→0.98" (weighs → counts).
Swing stamina costs are not scaled (only per-second drains).

## Loot tables ✅ (Round 5)

- **Scarcity**: most furniture rolls 1–2 (some 0–2) with 30–40 % empty
  containers and per-entry chances 0.5–0.95; nails come 5–20; a corpse
  carries a bandage ≈ 5 % of the time. Kitchen cabinets are pantries
  (food only, 2–3 rolls, never empty). A whole House A averages 5–11
  pickups over 50 world seeds (unit test).
- Tables are data (`data/loot/**.tres`, id = relative path): weighted
  entries with count range, chance and rarity tier (common ×1, uncommon
  ×0.6, rare ×0.3, very rare ×0.1), 0–N rolls, empty chance.
- `LootResolver.roll(table, rng, world_age)` is pure and deterministic.
  **World age** thins loot: every entry's chance × max(0.2, 1 − age/60)
  (day 30 = half, floor 20 % from day 48); an older world's container
  holds a subset of its day-0 contents.
- **Selection** by (building type, room type, container type), most
  specific first: `b/r/c`, `r/c`, `b/c`, `r_c`, `b_c`, `c`, `b/r`, `r`,
  `b`, `default`. Shipped: kitchen_cabinet, counter, fridge,
  bathroom_cabinet, bedroom_dresser, wardrobe, living_room_shelf, shelf,
  crate, garage/tool_crate, garage/shelf, zombie_corpse (small change,
  rag, sometimes a bandage / snack), convenience_store_shelf, default.

## Containers ✅ (Round 5)

`LootContainer` (interaction/): furniture boxes on layers 1+4. Loot is
rolled **the first time it is opened** (PZ style) from its table, seeded
by `WorldConfig.world_seed` + the container's stable `persist_id` — the
same world always has the same loot, reopening never re-rolls, and a
save only needs the `searched` flag + contents (`to_dict`).

| Action | Effect |
|---|---|
| Search <name> | 1.0 s busy "Rummaging…" (0.5 s on later opens; HUD bar), 3 m noise; getting hurt interrupts. Then the lid / door swings open and the loot window opens. |
| Close (or E / Esc / Tab, or walk > 2 m away, or die) | lid closes, window closes |

Events: `container_opened`, `container_closed`, `item_transferred(from,
to, item)`, `inventory_changed`. Zombie corpses are containers too
("Search corpse", `zombie_corpse` table, id `corpse/<spawner>/<n>` from
the spawner's monotonic counter — unique even for two spawners on one seed).

**Placement**: `BuildingPlan` rooms carry `room_type`; `furniture`
entries (type, room, position, rotation, optional container_type /
overrides / fixed items) reference `data/buildings/furniture_catalog.tres`.
House A: bed, dresser, wardrobe (bedroom); bathroom cabinet, toilet;
2 kitchen cabinets, counter, fridge (kitchen); sofa, shelf (living room)
— 8 containers. A 4×3 m garage (`shed_a.tres`, building type `shed`) at
(6, −16) with a tool crate, workbench and shelf, and a standalone
"Supply crate" at (10.9, −12.2).

## Inventory screen / loot window ✅ (Round 5, Round 6 — reference 4)

Round 6: **Tab** opens the player panel alone as the inventory screen.
The player panel has a **container column** (tabs: Inventory, the worn
bag) — the active tab is the list shown AND the target of everything
taken from a container (click a tab to loot into the bag). The
Inventory tab lists the equipped items first (gold; Type = Hands /
Both / Back / Hand 2), then the stacks grouped under category headers.
Interactions: click (container open: move; else select), Shift+click
one, **Ctrl+click splits half into a new stack in the same container**,
**right-click context menu** (`ItemActions`: Equip / Equip in secondary
hand / Wear on back / Unequip / Take off / Use (dressings bandage the
worst wound with THAT dressing; Eat / Drink are disabled "Round 7"
stubs) / Split stack / Drop / Drop one / Assign to hotbar 1-3; container
rows: Take / Take one), **G** drops the hovered (else selected) row at
the player's feet as a `WorldItem` (layer 4, child of the map — stays
in the scene), **drag and drop** (Control drag API) between the panels,
onto a container tab, or onto the player list. Clicks on the world do
not attack while the screen is open (nor any press that starts over
GUI). Taking into an equipment slot container is refused ("Use
Equip"). Rows are pooled and reconciled by item (only changed rows
rebind, no zebra striping so a removal re-styles nothing): refresh with
200 + 200 rows ≈ 7 ms, Loot All of 199 stacks ≈ 2 ms as one
transaction (`ItemContainer.begin_batch/end_batch`: one `changed` per
side, one encumbrance update) — `tests/integration/test_inventory_perf.gd`.
A **bag on the ground**
("Open School Bag" next to "Pick up") opens in the container panel like
furniture (instant, closes > 2 m away / on pickup). Bottom-centre
**hotbar widget** (3 slots, equipped one gold). Right-click on the UI
never starts aiming; clicks on the UI never attack.

Round 5 (unchanged):

Two panels along the top: left **Inventory** ("Transfer All", "1.80 / 20
kg"), right the container ("Loot All", "<name>", "W / cap kg"). Rows:
colour-square icon, name, type (Food / Drink / Med / Weapon / Tool / Mat
/ Cloth / Bag / Misc), ×count, kg, condition %. The HUD room label now
sits bottom-left above the status panel, never under the window.
The equipped weapon cannot be stored mid-swing ("Mid-swing"; Transfer
All skips it). Click = move the
stack, Shift-click = move one; rows that won't fit on the other side are
greyed with a "Too heavy" tooltip and refused with a footer notice.
Lists grow to 11 rows then scroll. Tab alone toggles the inventory
panel. Buttons never take keyboard focus (WASD keeps working).

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

## World time ✅ (Round 7)

`TimeManager` autoload (core/time_manager.gd) + pure `GameClock`
(core/game_clock.gd), tuning in `data/world/time_config.tres`
(`TimeConfig`).

- Game minutes since the start instant (float). Start: **1 July, 07:00**.
  1 real second = 1 game minute at 1× → a day lasts 24 real minutes.
- Calendar: real month lengths (no leap years), MM/DD date, seasons
  (Dec-Feb winter … Sep-Nov autumn), display temperature (seasonal mean
  1 °C Jan … 24 °C Jul + ±5 °C daily sine, coolest 03:00 / warmest
  15:00) → "°F" on the clock. Weather is a later round.
- Advances in `_physics_process` by the scaled physics delta; emits
  `time_advanced(from, to)` every tick and `minute_passed` /
  `hour_passed(hour, day)` / `day_passed(day)` once per whole unit (also
  for a large `advance(minutes)`). `set_minutes` / `set_time_of_day`
  jump without simulating (load, tests).
- Speed steps: **F5 pause · F6 1× · F7 2× · F8 4×**, `,` slower / `.`
  faster. Pause = `SceneTree.paused` (TimeManager keeps processing
  input). 2× / 4× = `Engine.time_scale` (the whole simulation, like PZ):
  refused "Can't fast-forward: danger" while any zombie chases the
  player, and dropped back to 1× ("Danger! Time back to normal") within
  0.25 s of one starting to.
- `WorldConfig._ready/_exit_tree` → `TimeManager.reset()` (minute 0, 1×,
  engine normal, unpaused) so every loaded map starts fresh and a freed
  map never leaves the engine sped up. `to_dict/from_dict`.

## Day / night lighting ✅ (Round 7)

`DayNightLighting` (world/, node "DayNight" in the map) drives the Sun
(DirectionalLight3D) and the WorldEnvironment from the hour
(`lighting_at(h)` pure, smoothstep between keyframes): daylight
07:00-18:30 (energy 0.85 = the Round 1-6 look), warm dusk 20:00, night
from 21:30 to 04:30 (faint cold moonlight 0.1, neutral dark-grey ambient
0.3 — never pitch black), pink-grey dawn 05:45. Every building room has a
warm shadowed SpotLight3D aimed at the floor whose cone just covers the
room (group `interior_light`, HouseBlockout `interior_lights`), on while
the sun is below 0.5 — no light bleeds through walls, it only escapes
through doorways / windows — and window panes glow warm
(`HouseWindow.set_night_glow`), like the lit houses of reference 3.
Round 8.5: parked emergency vehicles (`lights_at_night`) glow too
(`Vehicle.set_night_lights`, group `vehicle`); the node is in group
`day_night` so late vehicles pick the state up.

## Survival needs ✅ (Round 7)

`NeedsComponent` (survival/, child "Needs" of the player), pure maths in
`NeedsMath`, tuning in `data/survival/needs_profile.tres`
(`NeedsProfile`). Needs are StatsComponent stats 0 (fine) … 100.

| Need | Rate / game h | Levels (enter) | Effects |
|---|---|---|---|
| Hunger | +2.5 awake (×1.5 jog / sprint / climb), +1.2 asleep | Peckish 15 · Hungry 25 · Very Hungry 50 · Starving 80 | max stamina ×0.9 (hungry) / ×0.75; very hungry: no health regen, wounds heal ×0.5; starving: −6 HP / game h, wounds don't heal |
| Thirst | +3.5 awake (same exertion ×1.5), +1.8 asleep | Thirsty 25 · Parched 55 · Dying of Thirst 88 | max stamina ×0.9 / ×0.75 / ×0.6; parched: no regen, heal ×0.5, speed ×0.95; dying: −10 HP / game h, speed ×0.85 |
| Fatigue | +4 awake, −12.5 asleep, −2 resting | Tired 30 · Very Tired 55 · Exhausted 80 | stamina regen ×0.85 / ×0.7 / ×0.5; very tired swing ×1.1; exhausted speed ×0.9, swing ×1.2 |
| Sickness | −8 (recovers) | Queasy 20 · Nauseous 45 · Food Poisoning 70 | max stamina ×0.95 / 0.85 / 0.7; nauseous: no regen, −6 HP / h; poisoning −30 HP / h |

- Start 5 / 5 / 5 / 0. Eight game hours idle → Hungry + Thirsty. A
  normal day (16 h awake, 8 h asleep) costs ≈ 50 hunger / 70 thirst; no
  water → dead after ≈ 37 game hours (balance test: 36-48), no food ≈ 2.5
  days. Entering the second-worst level (Very Hungry, Parched, Very
  Tired, Nauseous) or the worst one gives a loud 4 s notice ("WARNING:
  Parched — drink something soon!", "DANGER: … you are losing health!")
  and the moodle pulses.
- Health drains go out as `EventBus.health_drained(character, amount,
  cause)` (bleeding / infection / needs) — never as `character_damaged`,
  so they don't interrupt actions.
- Levels use hysteresis: a level is left only 5 points below its enter
  value. Changes → `need_level_changed`, `moodles_changed`.
- Simulated in whole game-minute steps from `time_advanced`, so speed
  controls and sleep scale it; activity sampled per step.
- Effects applied on level change: `Character.set_stamina_max_multiplier
  (&"needs")` (combined with the injury penalty: `(base − Σ penalties) ×
  Π multipliers`), `StatsComponent.set_regen_multiplier(stamina)`,
  movement modifier `needs`, `Character.set_swing_time_multiplier`
  (MeleeCombat applies it on top of pain), `InjuryComponent
  .heal_multiplier`. Per step: health drain, or health regen +6 / game h
  when fed, watered, not sick and without wounds.

## Eating & drinking ✅ (Round 7)

`ConsumeAction` (survival/, child "Consume"). `FoodData`: `hunger` /
`thirst` (reductions), `eat_seconds`, `can_eat_half`, `requires_tool`
(item tag), `fallback_tool_tag` + `fallback_injury_chance`,
`empty_item_id`, `fresh_days` / `rotten_days`.

- Inventory context menu **Eat / Eat half / Drink / Drink half**
  (ItemActions `consume`, `consume_half`); "Use" and hotbar keys eat
  whole (food / drink can be assigned to the hotbar).
- Busy `eat` context for `eat_seconds × portion` ("Eating Canned Beans…"
  bar). The item (one of its stack) leaves its container at the start and
  goes back on interruption: damage (e.g. a zombie hit) or walking off.
  Nothing is consumed when interrupted.
- Half: the rest stays as a half-eaten item (`ItemInstance.portion` 0.5,
  weighs half, never stacks; row "Bread (50%)").
- Hunger reduction derives from calories: 1 hunger point = 25 kcal
  (`NeedsProfile.kcal_per_hunger`; beans 380 kcal = 15.2, bread 48, peanut
  butter 80); `FoodData.hunger` matches and is only used for 0-kcal items.
  House A's kitchen / fridge / counter feed one person ≈ 3.2 days on
  average (30-seed balance test: mean 2.5-7 days, every seed > 1 day).
- Refused "Paused" while the game is paused; "Fill bottle" disabled "No
  empty bottles" / "No room for the water".
- Canned beans: tin opener (tag `can_opener`) anywhere carried, else a
  knife (tag `blade`, hands included, not broken) with a 25 % chance of a
  hand scratch (3 dmg; the meal continues); neither → "Need a can opener".
- Water bottle → `water_bottle_empty` (misc, `fill_item_id`).
- Spoiled food: stale ×0.8 nutrition + 5 sickness, rotten ×0.5 + 45
  sickness (per whole item).
- **Sink** (`interaction/sink.gd`, kitchen + bathroom of House A):
  "Drink" (−60 thirst in 4 s; "Not thirsty" below 1), "Fill bottle"
  (all carried empty bottles in 2.5 s, only what the container weight
  allows; "No empty bottles"). The mains water runs until
  `WorldConfig.water_shutoff_day` (default 14, days since the outbreak =
  world_age_days + days played; < 0 never) → "The water is off".

## Spoilage ✅ (Round 7)

- `ItemInstance.created_minute` + lazily synced `age_minutes`: age grows
  by elapsed game minutes × the holding container's
  `ItemContainer.spoil_multiplier` (re-rated on every move). Fresh <
  `fresh_days`, stale < `rotten_days` (default 2 × fresh), then rotten.
  Canned / dry food never spoils. Saved ages are elapsed minutes; a
  loaded or reset clock bumps `TimeManager.epoch`, so items re-stamp
  instead of ageing whatever the load order.
- Lazily rolled container loot is as old as the world: age = (world_age_days
  × 1440 + game minutes so far) × the container's spoil rate (a fridge
  opened on day 40 holds rotten milk).
- Fridges (`furniture_catalog.tres` `spoil_multiplier` 0.25 →
  `LootContainer.spoil_multiplier`): bread / milk last 4× longer.
  Electricity is always on until a later round.
- Stacks only merge with the same spoil state (and whole portions); the
  merged stack keeps the older age. Inventory condition column shows
  Fresh / Stale (amber) / Rotten (red). Age and portion are saved in
  `to_dict` entries.

## Sleep & rest ✅ (Round 7)

`RestComponent` (survival/, child "Rest"); `RestFurniture`
(interaction/rest_furniture.gd) for beds (Sleep + Rest) and the sofa
(Rest), built by HouseBlockout from the catalog `interaction` key.

- **Sleep**: listed disabled "Not tired" below Tired; "Can't sleep:
  danger nearby" while chased or with a zombie within 15 m. Asleep =
  busy `sleep`, needs sleeping (fatigue −12.5 / h, hunger +1.2 / thirst
  +1.8 per h), `TimeManager.begin_sleep()`: `Engine.time_scale` 8
  (zombies get 192 s of simulated time in an 8 h night — Godot scales the
  step delta, not the tick count, so it costs no CPU) + game time at 20
  min / real s (8 h ≈ 24 s). Screen fades. Refused "Can't sleep:
  bleeding", and "Too thirsty / Too hungry to sleep" when the need would
  reach its critical level during the expected sleep. Wakes at fatigue 0
  ("You wake up rested"), on damage ("Woken: under attack!"), on a needs
  health drain ("Woken: dying of thirst"), on any sound within 8 m that
  reaches the sleeper or a zombie within 10 m / chasing ("Woken by
  noise!"), or after 600 real s. Wounds get the skipped game time.
- Busy actions end early through `Character.cancel_busy(context)`; any
  override (`begin_busy` while busy), cancel or death emits
  `Character.busy_cancelled(context)` and the owner restores its state:
  eating returns the item, bandaging refunds the dressing, a rummage
  never opens, sleep / rest end cleanly. Death also resets the game speed
  to 1×. The HUD state label shows the busy verb ("Eating", "Drinking",
  "Bandaging", "Searching", "Sleeping", "Resting", "Climbing").
- **Rest**: busy `rest` (stamina idle regen ×3 via the stats profile's
  `stamina_rest_multiplier`, fatigue −2 / h) until the player moves,
  gets hurt, or 1 h real.

## Character models & animation ✅ (Round 8.5)

Everything is procedural and owned (no third-party assets — see
`docs/ASSET_CREDITS.md`); Project Zomboid is only the style reference:
small, realistic-proportion people in everyday clothes, zombies = the
same townspeople gone grey, bloodied and hunched.

- **Body**: `HumanoidBuilder` (characters/models/) — 1.75 m, feet at
  y 0, facing −Z, right hand +X; 17 bones (hips, spine, chest, neck,
  head, upperarm / forearm / hand ×2, thigh / shin / foot ×2) with
  identity rest rotations; one rigidly skinned ArrayMesh of tapered
  prisms / ellipsoids / boxes: **584–764 triangles**, 2 surfaces (body in
  vertex colour + a tiny "eyes" surface for the mood material) → 2 draw
  calls per person. Head with nose, ears, eyes, hair (short / long / buzz
  / ponytail / bald), hats (cap, police cap, hard hat, fire helmet,
  beanie), shoes, belt, badge, hood, reflective stripes, hi-vis vest,
  open jacket strip, short sleeves / shorts showing skin.
- **Clothing as data**: `Outfit` resources in
  `data/characters/outfits/*.tres` (14: t-shirt & jeans, flannel, hoodie,
  leather jacket, green tee & khakis, winter coat, office worker, jogger,
  police officer, firefighter, construction worker, doctor, scrubs, and
  the player's `player_survivor`, which zombies never wear —
  `zombie_weight` 0). `Appearance` = outfit + skin tone (6) + hair (5
  styles × 6 colours) + height scale (0.94–1.05) + zombie decay;
  `Appearance.random(seed, outfits, zombie)` is deterministic.
- **Zombies**: the same builder with the skin turned grey-green /
  grey-blue / pale (`Appearance.zombie_skin`), faded filthy clothes,
  blood in coherent low-poly patches (heaviest down the front and on the
  hands, `blood` 0.35–1), torn sleeves (bare forearm + ragged cuff, 45 %
  per arm), dark eye sockets and a bloody mouth. A crowd picks from
  `CharacterAssets.ZOMBIE_VARIANTS` (48) looks, stratified so every outfit
  with `zombie_weight` > 0 gets ≥ 2 (rest by weight); a spawn seed maps to
  a look through `hash(seed)` (spawner seeds are all odd), so 200 zombies
  show ≥ 30 looks and every outfit while sharing ≤ 48 meshes. Height
  (0.94–1.05) comes from the seed on the model node, not the shared mesh.
  Zombie skin is a flat grey-green (~0.45, 0.50, 0.40); blood only on the
  chest / collar and lower sleeves in three shades (≤ 35 % of the torso);
  all cloth is muted (saturation ×0.75, value ≤ 0.75); everyone has dark
  eye sockets, nose and jaw bumps, zombies an open dark mouth. Bodies are
  chunky (thigh r 0.095, shin 0.07, upper arm 0.06, shoulders ±0.23,
  head ×1.15).
- **Animation**: `CharacterAnimations.build_library()` builds 31 clips
  in code (every clip keys all 17 bone rotations + the hips position):
  idle (breathing), walk, jog, sprint, sneak / sneak_idle (crouched),
  windup / strike × {2h, 1h, punch, shove}, climb, eat, search, bandage,
  sit, sleep (lying), death (fall on the back), hit (flinch); zombie
  z_idle (sway), z_walk (hunched limping shamble, one arm forward),
  z_chase (both arms reaching), z_attack (lunge → grab), z_bang (doors),
  z_knockdown, z_getup, z_death (face down), z_hit. Locomotion clips are
  speed-scaled against `DESIGN_SPEED` so feet do not slide.
- **`CharacterModel`** (Node3D): Skeleton3D + skinned MeshInstance3D +
  AnimationPlayer in **manual** process mode (the owner advances it);
  `play(clip, blend, speed)`, `advance(dt)`, `attach(bone)` →
  BoneAttachment3D. Shared resources in the `CharacterAssets` node (root).
- **Player**: `Visual/Model` (outfit `player_survivor`) + `Animator`
  (`CharacterAnimator`): dead → death; busy context → climb / eat /
  sleep / sit (rest) / search / bandage; MeleeCombat phase → windup
  (charging holds it) / strike, timed to the phase lengths (impact pose
  at the end of the active window); damage → 0.35 s flinch; else
  locomotion by effective mode + speed. The weapon (`MeleeVisuals`) is
  parented to the **right-hand bone** (the swing clips move it; the old
  procedural sweep only runs without a model); the worn bag is a box on
  the **chest bone** (back).
- **Zombie animation** (`ZombieVisual`): clip from the zombie's state /
  speed (`clip_for`: attack_door → z_bang, > 1.2 m/s → z_chase, moving →
  z_walk, else z_idle), the attack state's `lunge` scrubs z_attack, the
  bite (`flash`) plays the grab, hits play z_hit, knockdown / get-up /
  death their clips. **LOD**: advanced every 2nd physics tick when
  hostile within 12 m of its target or in a one-shot clip, every 3rd
  otherwise, every 6th for far "cheap movement" zombies; phases
  from `hash(seed)` (even over 0–5); the crowd starts desynchronised.
  A hit tints the body surface 30 % toward red for 0.08 s (vertex
  colours kept), sprays a CPUParticles3D blood burst and restarts z_hit;
  hand-placed zombies (seed 0) seed from their node path.

## Vehicles 🔶 (Round 8.5: parked only)

- **Data**: `VehicleData` (vehicles/, `data/vehicles/*.tres`): shape
  (sedan / wagon / pickup / van), length / width / belt / roof, wheel
  radius / wheelbase, cabin fractions, palette, trim, livery (police
  black-and-white doors + white roof, fire white roof + stripe), light
  bar + colours, pickup bed lockers, rust / flat-tyre chances, trunk
  label / capacities, `lights_at_night`. Six types: sedan, station wagon,
  pickup, van, police sedan, fire department pickup (ref 1).
- **`VehicleBuilder`** (pure, owned geometry, 486–582 tris): side profile
  with real wheel arches extruded across the width, tapered greenhouse
  (dark glass, body-colour pillars), wheels + hubcaps, bumpers, grille,
  head / tail lights, plate, mirrors, livery parts, open pickup bed.
  Surfaces body / glass / head / tail / beacon_a / beacon_b (mesh meta
  `surfaces`). `variation_for(data, seed)`: palette colour, fade, rust
  patches, a flat tyre (the car sags), a missing hubcap. A future
  VehicleBody3D reuses data + builder unchanged.
- **`Vehicle`** (StaticBody3D, layers 1 + 6, groups `vehicle`,
  `occluder`): one box collider (blocks movement, baked into the navmesh
  → zombies path around cars, fades when it hides the player), meshes
  cached per (type, seed) in `VehicleAssets`. Children
  `VehicleContainer` "Trunk" (rear; "Search trunk" / "Search truck bed" /
  "Search back of van", table `vehicle_trunk`, 1.5 s rummage) and
  "Glovebox" (driver's door, "Search glovebox", `vehicle_glovebox`) —
  layer-4 bodies outside the car so the interaction ray reaches them;
  persist ids `Vehicle/<name>/trunk|glovebox`.
- **Night**: `DayNightLighting` calls `set_night_lights(on)` on the
  `vehicle` group; emergency vehicles (`lights_at_night` + light bar)
  run the bar halves alternating at 2 Hz plus one OmniLight3D (range 4,
  energy 0.8, colour alternating with the bar), at most 4 such lights in
  the scene; parked cars keep head / tail lamps off.
- **Look**: paint muted (saturation ×0.75, value ≤ 0.75), road dirt
  (−25 %) below 0.35 m, rust patches on arches / sills, glass with a
  lighter sky band on top; a flat tyre is smaller and only its corner of
  the body sags (every wheel touches the ground). Faded by the occlusion
  manager a car keeps alpha ≥ 0.5 and writes depth (no x-ray of its
  inner faces). Meshes / materials: `VehicleAssets`.
- The map environment uses tonemap exposure 0.85 (muted daylight, ref 2).
- **Map**: the blue box "Car" is gone; test_ground has 7 parked vehicles
  (police car at the old spot, sedan ×2, pickup, wagon, van, fire pickup)
  along the road (x ±7.6, z 17–34), plus a yellow centre line.

## Planned (see MASTER_PLAN for order)

Sound propagation ✅ · Combat ✅ (melee) · Health & injuries ✅ · Inventory ✅ (equipment, bags, encumbrance) ·
Loot tables ✅ · Needs ✅ (hunger / thirst / fatigue / sickness; temperature, wetness, stress ⬜) ·
Barricades ⬜ · Save/load ⬜ · Crafting ⬜ · World time ✅ · Vehicles 🔶 (parked, R8.5) · Character models ✅ (R8.5) ·
Farming ⬜ · Weather ⬜ · Electricity ⬜ · Zombie population sim ⬜ ·
World streaming ⬜ · NPC survivors ⬜
