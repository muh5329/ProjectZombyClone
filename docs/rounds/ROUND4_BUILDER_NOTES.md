# Round 4 — builder notes (melee combat, shove, body-region injuries)

## What was built

- **Items as data** (`items/`): `ItemData` (id, display_name, category,
  weight, max_stack, max_condition, color, world_size), `WeaponData
  extends ItemData` (damage range, crit chance/multiplier, head-hit
  chance, reach, arc, max targets, swing time + windup/active fractions,
  stamina, knockback, knockdown + knockdown-vs-windup, `is_shove`,
  condition loss chance/amount, noise radius), `ItemInstance`
  (condition, stack, `wear()`/`broken`, dict round trip), `WorldItem`
  (layer 4, "Pick up <name>"). `data/items/weapons/`: baseball_bat,
  crowbar, kitchen_knife, hammer, pipe, plus fists and shove.
- **Combat** (`combat/melee_combat.gd`, generic `MeleeCombat` child
  `Combat`): charge (×0.6 → ×1.3 over 1 s), stamina paid at swing start
  or `attack_refused("Too tired to swing")`, windup → active (sphere
  query on layer 3 → pure `select_targets` → LOS ray 1+7+8) → recovery,
  queued next attack, shove through the same pipeline, damage × charge ×
  stamina multiplier, crits, head hits, knockback, knockdown rolls,
  condition wear + break → fists, `melee` sound. `scripted` flag + public
  API (`start_attack/release_attack/attack_now/shove/set_aiming`,
  settable `aim_direction`) for tests and future NPCs.
- **Player input** (`player/player_combat_input.gd`): LMB/RMB/Space/X/B;
  ortho-safe mouse → ground (`project_ray_origin/normal` + plane).
  `PlayerController` caps the mode at walk while aiming;
  `Character.facing_override` makes the body face the aim / swing.
- **Visuals** (`combat/melee_visuals.gd`): weapon box on the body visual
  that sweeps through the arc, aim ring at reach (orange with targets) +
  arc preview, bright ground arc during the active window.
- **Zombies**: `take_damage` info (`region`, `knockback_dir`,
  `knockback`, `knockdown`), ×1.5 while down, stun ≥ 10, collided
  knockback slide, hit flash, attacker becomes target;
  `receive_shove()`, `is_winding_up()`, `is_knocked_down()`; new
  `ZombieStateKnockedDown` (2.5 s, lies on its back, gets up); stun
  duration per cause; bites roll region + type (`roll_attack_info`). All
  tuning in `ZombieProfile` (region/type weights, knockdown, knockback
  speed, shove stun, hit flash; `stagger_damage` 20 → 10).
- **Injuries** (`injuries/`): `Injury` (10 regions, 6 types, pure
  `roll_weighted`), `InjuryTypeSpec`, `InjuryComponent` (child
  `Injuries`, wired by `Character._ready`) with bleeding (health drain +
  blood drips), leg slow (`injury` modifier), max stamina reduction,
  `pain` + `infection` stats, bandaging (B, 4 s busy), glass laceration
  on smashed-window climbs. Data: `data/injuries/injury_profile.gd` +
  `human_injuries.tres`.
- **Engine-side helpers**: `HealthComponent.drain()` +
  `EventBus.health_changed`; `StatsComponent.set_max()`; stamina rate
  for the `bandage` busy context.
- **Map**: bat in the living room (-6.5, -3.2), knife in the kitchen
  (-5.2, -8.8), `BloodDecals` node (MultiMesh pool of 200).
- **HUD**: top-right body panel (weapon + condition bar, pain %,
  INFECTED, injury list with BLEEDING / (bandaged)), "Aiming — N in
  reach", notices for refusals / pickups / bandaging / broken weapons;
  stamina shown against the base max with "(max N%)"; health bar follows
  `health_changed`; new key hints. HUD containers no longer eat mouse
  clicks (`mouse_filter = ignore`).
- **Input map**: `shove` (Space), `cycle_weapon` (X), `bandage` (B);
  `attack`/`aim` already existed.
- **Docs**: SYSTEMS (combat, injuries, items, decals, HUD, zombie
  states), ARCHITECTURE (folders, types, events, layers, groups),
  KNOWN_ISSUES (new gaps section, mouse aim fixed), README controls.

## Tests

`scripts/test.sh`: **142 tests, 0 failed** (67 unit, 75 integration), no SCRIPT ERROR / ERROR lines
(~210 s; Round 3 had 112).

- Unit (+13): `test_combat_math.gd` (arc selection reach/angle/radius
  widening/knife arc; caps, ordering and degenerate inputs; charge curve
  incl. monotonicity; stamina multiplier; distinct weapon numbers for all
  7 WeaponData; ItemInstance wear/break/dict), `test_injuries.gd` (region
  weights sum to 1 for default / glass / zombie + type weights, ids
  valid, glass never head/neck; `roll_weighted` edges + distribution;
  infection chances; bleed rate + bandage; leg slow incl. bandaged and
  floor; pain / max-stamina sums and caps; labels/dicts).
- Integration (+17, `test_combat_scene.gd`, real scene): bat hit (stamina
  paid at start, event payloads, damage range × charge, arc visible in
  the active window, hit flash, melee sound, blood decal, knockback,
  target switch, stagger); miss behind + no hit through the Wall prop;
  knife 1 target vs bat 3 targets on the same line-up; knockdown (event,
  lying visual, ×1.5, no bites while down, gets up after 2.5 s); shove
  cancels a windup (no bite lands, pushed ≥ 0.8 m, no damage, stagger) and
  a knockdown shove; stamina refusal (event, HUD notice, shove refusal,
  fists still work); condition loss (not on a miss, HUD (1/2), break →
  fists, dropped from hands, HUD + notice); queued attack (tap + held);
  aim (camera round trip mouse → ground, different pixel → different
  point, facing, HUD "N in reach", ring, walk cap while facing the aim);
  zombie bite → region/type from profile weights + HUD list, bite always
  infects, infection +2 % per 100 s, INFECTED + pain on HUD, lethal drain
  at 100 %; bleeding drain (no hit flash), drips, HUD health, stops after
  bleed_seconds, decal pool capped at 200; bandage (worst first, 4 s busy,
  no walking / swinging, HUD "(bandaged)", second via the real B action,
  "Nothing to bandage"); leg slow + max stamina + pain stat; smashed
  window climb lacerates (glass regions, no infection, 4 damage); pickup
  bat + knife through PlayerInteraction, auto-equip, cycle via API and the
  real X action; balance: 4 zombies kill a standing player in < 30 s
  (≈ 4.6 s) and bat + shove beat one zombie losing ≤ 40 % (0 % across
  seeds 1–3, 2–5 swings).
- Existing: the Round-3 attack test now tolerates the bite's bleeding
  (health checks ±1 hp / 0.05).

`scripts/screenshots.sh`: `SCREENSHOT_RUN: OK`. New shots (checked by the
run): `14_aim_arc` (E-pickup of the bat, RMB + mouse aim, orange ring,
arc preview, "Aiming — 3 in reach"), `15_swing_hit` (LMB charge/release,
three zombies hit and flashing), `16_knockdown` (zombies lying after
shove / swing), `17_injury_panel` (smash + climb the west window with
1-4 / E → glass laceration, BLEEDING list), `18_bandaging` (B →
"Bandaging left hand…", busy, bandaged after 4 s).

`scripts/perf.sh`: calm **4.2–4.6 ms**, hostile **7.8–8.4 ms** (budgets 8 / 10).

## Failed approaches / gotchas

- `physics_frame` is not in scope in a `test_case.gd` subclass (it is a
  RefCounted, not the SceneTree) → `await tree.physics_frame`.
- Bleeding via `take_damage` would have flashed the HUD and created a new
  wound every tick → `HealthComponent.drain()` + `health_changed`.
- Showing stamina as value / current max read 100 % right after a swing
  whenever a new wound lowered the max (the clamp swallowed the cost) →
  HUD shows it against the base max.
- Emitting `weapon_equipped` with `Signal.emit.call_deferred` captured
  the actor even if it was freed first → deferred method on the node.
- Screenshot staging: zombies placed "up-screen" of the player were
  hidden behind it in the dimetric view and walked onto the arc before
  the aim shot → placed screen-right, 1.5 m, senses off until shot 14.
- Square blood quads read as tiles → flat 9-sided discs, randomly
  stretched.

## Critic pass (fixes applied)

1. Queue survived interrupted swings → `SwingStateMachine.finish()` returns
   the snapshot and always clears it (test `test_b1_…`).
2. Weapon swap mid-swing dodged wear → the swung ItemInstance is captured
   at swing start; `Player.cycle_weapon()` refuses "Mid-swing"
   (`test_b2_…`).
3. Knockdown zeroed its own knockback → kept (`test_b3_…`, shove
   knockdown slides ≥ 1 m).
4. Decal height from the hit position.
5. Damage interrupts bandaging (`bandage_interrupted`, "Interrupted");
   B only treats bleeding wounds by `bandage_priority` (fractures refused).
6–7. Balance: zombie stagger 16 / stun 0.5 s / 1.2 s stagger immunity /
   windup 0.4 / range 1.0; bat knockback 0.3, knockdown 15 %, head 12 %,
   swing 1.1 s, stamina 12, 2 targets; crowbar / pipe / hammer knockback
   and knockdown lowered; knife `can_stagger = false`. Critic's bot, seeds
   1–5: 1v1 bat 12/25/27/24/25 % (avg 23 %), 3 zombies: dead ×5; passive
   surrounded player dies in ≈ 5 s. Landed first try, no iteration.
   Found on the way: despawned zombies kept their attack slot (static
   registry) → released in `Zombie._exit_tree` with the key remembered at
   claim time.
8. Infection hidden until 25 ("Feverish", orange), 60 ("Infected", red).
9. Pain > 50 / > 80 → damage ×0.85 / ×0.7, swing time ×1.15 / ×1.3
   (thresholds in the injury profile).
10. HUD charge meter, bandage progress bar, "Stamina 60 % · max 80 %",
    "Idle", hint strip; zombie head tint restored after the hit flash;
    bat 0.8 × 0.07 m held at the side, tip up at rest.
11. `melee_combat.gd` split into `SwingStateMachine` + `HitResolver` +
    facade; `CombatProfile` (data/combat/); bandage priority in the injury
    profile. Hit height 1.1 m (clears window sills).
12. Tests: closed door leaf / closed pane block swings (open window
    doesn't), damage interrupts bandage, stagger immunity + knife, pain,
    HUD meters/format, SwingStateMachine unit test, pain/infection-stage
    and bandage-priority unit tests.

Totals after the critic pass: **154 tests, 0 failed** (70 unit, 84
integration, ~335 s). Perf: calm 4.2 ms, hostile 8.2 ms.

## Not finished / left for the critic

- See KNOWN_ISSUES "Round-4 combat / injury gaps": upright capsule while
  knocked down, one-shot target resolution per swing, no animations / hit
  reactions, free bandages, always-lacerating glass, no infection stages,
  pain without effect, stopgap `held_items`, easy 1v1 balance.
- `PROGRESS.md` intentionally not written. Nothing committed.
