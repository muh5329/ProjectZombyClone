# Project Zomb — handoff README

Isometric 3D survival sandbox in **Godot 4.6 / GDScript**, inspired by the
systemic gameplay of Project Zomboid. Blockout visuals (primitives), systems
first. Built through a "gauntlet" of verified rounds; **All 10 rounds (+8.5 models) of the first vertical slice are done and
committed. Next per the brief: a full vertical-slice review before
expanding the world.**

## Status at handoff (2026-09-22)

| Round | Scope | Status |
|---|---|---|
| 1 | Player controller (sneak/walk/jog/sprint), stamina economy, isometric camera, HUD, test harness | ✅ done |
| 2 | Interaction framework, enterable house (doors, windows, climb/smash), orthographic dimetric camera, roof/wall cutaway | ✅ done |
| 3 | Zombie AI (FSM, vision/hearing/proximity, navmesh, door banging), health, spawner, perf harness | ✅ done |
| 4 | Melee combat, shove, body-region injuries, weapons as data | ✅ done |
| 5 | Containers, data-driven loot tables, player inventory, ref-4 loot window | ✅ done |
| 6 | Equipment slots, bags, hotbar, inventory screen, encumbrance | ✅ done |
| 7 | World time, day/night, hunger/thirst/fatigue, food + water, spoilage, sleep | ✅ done |
| 8 | Sound propagation, attenuation, hearing, moans, noise UI, glass | ✅ done |
| 8.5 | Procedural people, zombies (48 looks, 31 animations) and 6 vehicle types | ✅ done |
| 9 | Barricades, furniture blocking, disassembly, carpentry, zombies breaking in | ✅ done |
| 10 | Save/load of the whole world, menus, natural-play acceptance test (3 seeds) | ✅ done |

- **417 automated tests, 0 failing** (`scripts/test.sh unit` ~7 s, then `integration-a`/`-b`/`-c`/`-d` ~265–355 s each; run them as separate calls).
- Perf harness: 200 zombies calm 4.2 ms / all hostile 8.4 ms avg physics
  step on a 2-core box (`scripts/perf.sh`).
- Screenshot evidence run through the real input map (`scripts/screenshots.sh`,
  13 shots into `tests/output/`).
- Git history: one commit per round; nothing uncommitted.

## Run the game
Open `project.godot` in Godot **4.6** and press Play (main scene: the
title screen `ui/menus/main_menu.tscn` — New game loads
`maps/test_ground.tscn`; Continue / Load open a save). Controls: WASD move · Shift sprint · Ctrl sneak ·
Alt walk · E interact · 4-7 pick action · 1-3 hotbar · LMB attack
(hold to charge) · RMB aim · Space shove · X cycle weapon · B bandage ·
Tab inventory (right-click items, drag, Ctrl+click split, G drop) · Q/R
rotate camera · wheel or +/− zoom · F5-F8 (or , .) time speed · H shout · F3 debug · F4 sound debug · R restart after death · F9 quick-save ·
F10 quick-load · Esc pause menu (Save / Load / Quit). Beds: Sleep / Rest, sofa: Rest, sinks: Drink / Fill bottle; right-click food: Eat / Eat half.

## Run the tests
```
GODOT=/path/to/godot scripts/test.sh                 # all (unit + integration)
GODOT=/path/to/godot scripts/test.sh unit
GODOT=/path/to/godot scripts/test.sh integration-a       # a quarter of the integration files
GODOT=/path/to/godot scripts/test.sh integration-b       # … -c, -d: the other quarters (--shard=K/N also works)
GODOT=/path/to/godot scripts/test.sh --filter=zombie
GODOT=/path/to/godot scripts/screenshots.sh          # real-input gameplay run + PNGs
GODOT=/path/to/godot scripts/perf.sh                 # 200-zombie benchmark
```
macOS: `GODOT="/Applications/Godot.app/Contents/MacOS/Godot"`. Linux CI uses
`xvfb-run` automatically for screenshots. `test.sh` fails on any
`SCRIPT ERROR` or `ERROR:` line in engine output.

## Read these first (in order)
1. `docs/AGENT_GUIDE.md` — conventions, commands, definition of done, visual target.
2. `docs/BRIEF.md` — the original design brief (verbatim).
3. `docs/MASTER_PLAN.md` — round table and phases.
4. `docs/PROGRESS.md` — per-round log: what changed, tests, bugs found by the
   independent critic, failed approaches, verifier scores.
5. `docs/ARCHITECTURE.md` — folder layout, key types, signals, layers.
6. `docs/SYSTEMS.md` — each gameplay system, its numbers and its hooks.
7. `docs/KNOWN_ISSUES.md` — open issues by priority.
8. `docs/rounds/ROUND*_BUILDER_NOTES.md` — builder notes per round.
9. `docs/reference/ref1..4*.png` — the four Project Zomboid reference
   screenshots the look is being matched to (camera, cutaway, night, loot UI).

## Architecture in one paragraph
Characters are `CharacterBody3D` + small logic components (`MovementComponent`,
`StatsComponent`, `HealthComponent`); they receive *intent* (`set_intent`)
from a `PlayerController` or an AI, never read `Input` themselves. Systems talk
through the `EventBus` autoload only. Content is `Resource` data under `data/`
(`CharacterStatsProfile`, `ZombieProfile`, `BuildingPlan`). Objects provide
their own interactions via an `Interactable` component (`get_actions` /
`perform`); the player never switches on object types. Buildings are generated
from a plan; an `OcclusionManager` hides roofs and stubs camera-facing walls
when the player is indoors. Zombies run a generic RefCounted `StateMachine`
with staggered senses and navmesh pathing; door leaves are on physics layer 7
and window panes on layer 8 so navigation and line-of-sight work.

Physics layers: 1 world · 2 player · 3 zombies · 4 interactables · 5 items ·
6 occluders · 7 doors · 8 window panes.

## The process to keep following (gauntlet)
Per round: read docs → run the game/tests → pick ONE improvement → implement
(builder agent) → tests + screenshots → **independent adversarial critic** that
writes throwaway probe tests and reports bugs/architecture/UX/test gaps with
0-10 verifier scores → fix everything → re-run from clean → PROGRESS.md entry →
commit. Every round so far found 5–14 real defects in the critic pass; do not
skip it.

## Round 4 spec (DONE — kept for reference; see PROGRESS.md) — melee, shove, injuries
- `items/item_data.gd`, `items/weapon_data.gd` (damage min/max, reach, arc,
  swing time, stamina cost, knockback, knockdown chance, max targets,
  condition loss, noise), `items/item_instance.gd` (condition/stack);
  `data/items/weapons/{baseball_bat,crowbar,kitchen_knife,hammer,pipe}.tres`.
- `combat/melee_combat.gd` on the player: windup → arc shape-cast on layer 3
  → up to `max_targets` → damage × charge × exhaustion penalty, head-hit
  chance, knockback, knockdown (new `KnockedDown` zombie state, ×1.5 damage
  while down), condition loss, `melee_swing` / `melee_hit` events + sound.
  Fists as default. Attack refused when stamina too low (HUD notice).
- Aim mode (RMB): face mouse-on-ground, walk speed, ground ring at reach,
  "N in reach"; hold LMB to charge (×0.6→1.3 over 1 s).
- Shove (Space): 1.0 m / 90° / 3 targets, knockback 1.2 m, 25 % knockdown
  (50 % vs winding-up zombie), stamina 5, cancels zombie attacks.
- `injuries/injury.gd` + `injury_component.gd`: region enum (10 parts),
  types scratch/laceration/deep wound/bite/burn/fracture, bleeding drains
  health, leg injuries slow (movement modifier `injury`), max stamina
  reduction, pain stat, infection (bite 100 %, scratch 7 %, laceration
  25 %). Zombie attacks roll region + type; smashed-window climb lacerates.
  `B` = bandage worst bleeding wound (4 s busy; items come in R5/6).
- Minimal pickup/equip: `items/world_item.gd` on layer 4 ("Pick up"), bat in
  the living room, knife in the kitchen, `X` cycles weapon; HUD shows weapon
  + condition and an injuries list. Blood decal pool (max 200).
- Tests: arc selection (pure), charge curve, injury effects, integration for
  hit/miss/multi-target/knockdown/shove/stamina refusal/condition loss/
  bleeding/bandage/leg slow/pickup+cycle/aim, plus two balance checks
  (surrounded player dies < 30 s; bat + shove beats one zombie losing ≤ 40 %
  health). Screenshots 14–18. `scripts/perf.sh` must still pass.

## Known gaps worth knowing (see KNOWN_ISSUES.md)
Cutaway is facade-wide (not per-ray); one occlusion ray; hearing is a radius
with wall halving only; no animations (state = head tint, lunge tell);
far calm zombies use a cheap out-of-physics navmesh slide; no mouse aim yet;
the screenshot runner is Linux/Xvfb-oriented (works on macOS with a display).

## Tooling notes
- Godot Linux build used for CI lives outside the repo
  (`/home/claude/tools/godot` in the original environment); set `GODOT`.
- Hand-written `.tscn`: all `[ext_resource]` before `[sub_resource]`.
- SceneTree `-s` runner scripts must not statically type gameplay classes
  (they compile before autoloads exist).
- GDScript lambdas capture locals by value — use an Array holder.
