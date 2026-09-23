# Round 8 — builder notes (sound propagation + zombie hearing)

## Decisions

- **Gameplay sound is its own system** (`audio/`), not audio playback:
  `SoundManager` autoload with `emit_sound(category, position, source,
  overrides)`. Categories are data (`data/audio/sound_categories.tres`,
  23 entries incl. future alarm / gunshot / generator / vehicle).
  Overrides replace radius / intensity / duration; anything else goes to
  `event.extras` (a moan's `lure` + `hops`). Weapons keep their own
  `noise_radius` as a per-event override (bat 8, knife 2; shove data
  raised 2 → 5 m to match the category).
- **EventBus.sound_emitted stays** (UI, sleep wake, debug) but is emitted
  only by SoundManager. Zombies no longer connect to it: 200 signal
  callbacks per footstep are gone.
- **Dispatch is synchronous, once, O(listeners near)**: a `SpatialHash`
  (8 m cells) of listener ears refreshed at 5 Hz; query radius =
  radius × 2 (max sensitivity) × masking + 2 m slack; exact distance test
  after. Events are kept for `duration` only for rings / debug.
- **Attenuation with ≤ 2 rays per (event, listener)**: sound → ear; on a
  hit, ear → sound. Different colliders = two obstacles. Kinds come from
  the collider (`sound_obstacle_kind()` on WallFixture / Door /
  HouseWindow, a pane asks its window; group `wall` → wall; anything else
  → prop ×0.85). Product clamped at 0.15. Cached per event by the ear's
  0.5 m cell (crowds share rays).
- **Openings**: only for sounds inside a building heard by ears outside
  it, on the outward side of an open exterior door / window of that
  building: slack via = radius × att(sound → opening) − d(sound, opening)
  − d(opening, ear); one ray per opening per event (cached). The outward
  half-space test is what stops the smashed-window path from "leaking"
  to a zombie behind the house.
- **Strength, not radius, drives reactions**: `perceived = intensity ×
  slack / full radius`. ≥ 0.4 → investigate at chase speed; fainter →
  face it, stand 0.8 s, shamble. Priority: re-target only if new ≥
  current − 0.05/s × age. Lost-target / hit-by-something investigations
  use `investigate_quietly` (strength 0, walk, no pause) — Round 3-7
  behaviour unchanged.
- **Moans**: an investigating zombie moans every 10 s (6 m, intensity
  0.25); hearers go to the moaner's GOAL (`lure`), not the moaner;
  `hops` stops relays after 2. The Round-3 `hearing_wall_attenuation`
  profile field is removed.
- **Glass** is a hazard node (`GlassShards`, child of the window), not an
  item: 1.2 × 1.6 m across the wall, so the climb landing point (0.9 m)
  is just outside it. Per-tick chance 1 − (1 − 0.1)^dt so crossing fast is
  safer than lingering; 1.5 s cooldown; not while sneaking / busy / with
  a `shoes`-tagged equipped item (none exist yet). "Remove broken glass"
  (2 s busy `clear_glass`) removes floor + frame shards and the climb
  hazard.
- **Feedback**: NoiseRings pool (20 shader rings on PlaneMeshes, one
  material each — no per-instance uniforms needed under Compatibility),
  player sounds only; HUD NoiseMeter; F4 SoundDebugOverlay
  (ImmediateMesh, no depth test; zero cost while off).
- **Shout** (H): `ShoutComponent` child "Shout", 3 stamina, 1 s cooldown
  (numbers in CharacterStatsProfile "Voice"), routed through
  PlayerCombatInput with the other action keys.

## What was built

- audio/: `sound_manager.gd` (autoload SoundManager), `sound_event.gd`,
  `sound_category.gd`, `sound_category_table.gd`, `sound_math.gd`,
  `spatial_hash.gd`; data/audio/`sound_categories.tres`.
- Emitters migrated: FootstepEmitter (categories per mode, exports
  removed), Door (open / close / bang / break; `close_door(actor)`),
  HouseWindow (open / close / smash with the actor as source), HitResolver
  (melee_hit / shove), MeleeCombat (melee_swing), ContainerAccess
  (rummage), ConsumeAction (eat / bottle_fill), ShoutComponent (shout),
  ZombieAI (zombie_moan).
- Zombies: ZombieSenses is a listener (`sound_ear_position`,
  `sound_sensitivity`, `sound_owner`, `on_sound`, `last_heard`),
  registers in setup / `_enter_tree`, unregisters on death and
  `_exit_tree`; `sound_heard(position, category, strength, event)`;
  ZombieAI priority / loudness / moan / `investigate_quietly`;
  investigate state pause + JOG when loud. Profile: loud_sound_strength,
  faint_turn_seconds, sound_priority_decay, moan_cooldown, moan_max_hops.
- Interaction: WallFixture sound API; window glass + "Remove broken
  glass"; `interaction/glass_shards.gd`.
- Effects / UI: `effects/noise_rings.gd` + `noise_ring.gdshader`,
  `effects/sound_debug_overlay.gd` (both nodes in test_ground.tscn),
  `ui/hud/noise_meter.gd`; HUD notices / busy label / hints.
- Input: `shout` (H), `toggle_sound_debug` (F4) → GameManager.sound_debug.
- EventBus: `shouted(character, ok, reason)`, `hazard_hurt(character,
  hazard, region)`.
- perf: `--noisy` mode (30 random events / s from inside the measured
  bracket), `scripts/perf.sh --noisy` runs it alone; the full perf.sh
  runs calm + hostile + noisy.

## Tests

- Unit `test_sound.gd` (10): attenuation (walls, doors open / closed,
  windows, min clamp, unknown kinds), effective radius / slack /
  perceived, via-opening slack + outward side, priority rules, category
  data (21 ids + radii), spatial hash insert / update / remove / query,
  SoundEvent weak source, dispatch by radius / sensitivity / masking /
  overrides / extras, own-source skip + unregister, freed-listener prune,
  collider classification.
- Integration `test_sound_scene.gd` (12): sneaking 4 m behind an idle
  zombie not heard / sprinting heard; window smash heard 15 m in front of
  the smashed window, not 15 m behind two walls; closed vs open front
  door (11 m in line hears, 6.6 m behind the wall doesn't); sound escapes
  around a corner through the doorway (`path = opening`); shout via the
  H action lures a zombie 18 m away (stamina, cooldown, notice); loud →
  chase speed, faint → turn then shamble, priority ignore / re-target;
  moan recruits a neighbour to the lure (hop 1, cooldown); a zombie's
  door bang recruits another; glass: sneaking safe, walking scratches a
  leg (+ event + notice), Remove broken glass 2 s busy clears floor +
  frame; rings only for player sounds (+ radius, pool cap, fade) and HUD
  meter LOUD; F4 overlay draws circles + hearing lines and toggles off;
  listener cleanup on die / queue_free / scene free.
- Updated: door bang 12 m + `door_break` category (test_health), melee
  `melee_hit` (combat), `footstep_jog` (inventory), sleep-noise tests use
  SoundManager, zombie door test uses SoundManager, window actions list
  (+ Remove broken glass), house number-key test (4 actions now).
- Screenshots `26_noise_rings` (sprint + smash from outside via key 5,
  20 m ring mid-expansion — slow-motion for the shot — zombies turning,
  meter LOUD, glass shards) and `27_debug_sound` (F4 + H shout: circles
  and hearing lines).

## Numbers

`scripts/test.sh unit` 132 tests, `scripts/test.sh integration` 178
tests (+12), 0 failed. `scripts/perf.sh`: calm 2.8 ms, hostile 5.8 ms,
noisy 3.0 ms (485 events incl. moans, ~7.9 k rays, ~7.3 k deliveries in
10 s). `scripts/screenshots.sh`: OK (27 shots).

## Gotchas

- `PlayerInteraction.current_target` is the Interactable component, not
  the fixture (compare `get_parent()`).
- Noise rings animate on process (real) time: at ~7 fps under Xvfb a
  20 m ring is past the screen edge by the time `_shot` renders, hence
  `Engine.time_scale = 0.05` for shot 26.
- Footsteps fire after 1 s of movement (accumulator), so short scripted
  moves (< 60 physics frames) make no step sounds.
- A GDScript `Dictionary = {}` default is avoided for the per-event
  cache (`evaluate(…, p_ctx: Variant = null)`).

## Critic fixes

1. **Iterative attenuation**: one ray sound → ear, re-cast past each hit
   body (exclude list, ≤ 5 obstacles), every obstacle multiplies — three
   walls now clamp at 0.15 instead of counting as two, and a sofa in
   front of a wall no longer hides the wall (the two-ray model made
   furniture *raise* loudness). Cache per event by 1.5 m ear cell.
2. `hit_from_inside` on; door / window sounds start 0.3 m off the
   opening on the actor's side (`WallFixture.sound_position`), and a
   door's close sound fires when the swing ends — a door shut inside is
   muffled for a zombie outside.
3. `emit_sound` rejects non-finite positions / radii (warning, null).
4. `_expire` filters the whole list (a short event behind a long alarm).
5. Openings in both directions and building → building (A's opening +
   B's opening, middle leg assumed clear). Ear buildings cached per
   listener at 5 Hz. Test: a zombie in the living room hears a street
   shout through the open front door (`path = opening`).
6. Re-targeting while investigating keeps max(loud), min(hops),
   max(strength).
7. Dead player: shout refused silently, no rings, meter ignores it;
   `SoundCategoryTable.player_loud_radius` (10 m) is the one LOUD
   number for meter and rings.
8. Sleep: RestComponent is a SoundManager listener while asleep; wakes
   at `NeedsProfile.wake_sound_strength` (0.1) or a zombie within 10 m
   with eye-to-eye line of sight. The R7 "zombie reaches the house"
   test now opens the doors (a zombie outside a closed house no longer
   wakes you through the walls).
9. Glass: 1.2 m each side (2.4 m deep, 40 larger brighter shards, a
   sibling of the window so the cutaway never fades it), 25 %/s,
   climbing with glass 40 % laceration (data), removal 3 s + 3 m
   `glass_clear` noise.
10. Shout 6 stamina / 3 s; zombies that reach a lure (`shout`) search
    8–12 s with widening shuffles (ZombieStateSearch.lure).
11. perf: p99 budgets (16 ms) in every mode, `--horde-noise` (60 clustered
    + 10 smashes / s; avg ≤ 10, p99 ≤ 20). Moans go through
    `SoundManager.queue_sound` (≤ 2 per physics frame). Numbers: calm
    2.9 / p99 6.0, hostile 5.7 / 8.1, noisy 2.8 / 5.4, horde 1.0 / 3.2 ms.
12. Smashed windows hide the permanently disabled Open / Close entries;
    F4 labels hearing lines with the perceived strength (Label3D pool)
    and does no work while off.
Also: OcclusionManager's mesh loops were typed and crashed on a freed
mesh (glass removal) — now untyped + validity-checked.
