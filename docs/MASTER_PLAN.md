# Project Zomb — Master Plan

Isometric 3D survival sandbox in **Godot 4.6 / GDScript**, inspired by the
systemic gameplay of Project Zomboid. Blockout graphics first; systems over
visuals; expand only through verified vertical slices.

The full design brief lives in `docs/BRIEF.md` (verbatim from the project
owner). This file is the *working* plan: what we are building, in what order,
and what "done" means for each step.

## Non-negotiables

1. **Systemic** — systems interact (noise → zombies, wet → cold → stamina…).
2. **Persistent** — world changes survive save/load and chunk unload.
3. **Data-driven** — items, recipes, loot, zombies, buildings are resources.
4. **Verified** — nothing is "done" until it works in the running game and a
   test or scripted run proves it. See `docs/PROGRESS.md` for the evidence.
5. **Vulnerable human** — movement, combat and needs must never feel like an
   action-RPG. Small groups of zombies stay dangerous.

## Verifier rubric (score each round 0–10)

Functionality · System Integration · Survival Depth · Architecture ·
Performance · UX/Feedback · Bug Resistance.
A round passes only with no critical errors, no regressions, working in real
gameplay, and independent verification.

## Gauntlet rounds (first vertical slice)

| # | Round | Status |
|---|-------|--------|
| 1 | Player + isometric camera | **DONE** (2026-09-22, 39 tests) |
| 2 | One enterable house with doors and windows (+ roof/wall occlusion) | **DONE** (2026-09-22, 81 tests) |
| 3 | Basic zombie AI (states, senses, navigation) | **DONE** (2026-09-22, 112 tests) |
| 4 | Melee combat and player health | next |
| 5 | Interactable containers and loot (data-driven loot tables) | |
| 6 | Inventory and equipment (weight, encumbrance → movement) | |
| 7 | Hunger / thirst + consumable food | |
| 8 | Sound propagation + zombie hearing | |
| 9 | Barricading windows and doors | |
| 10 | Saving and restoring the entire micro-world | |

After Round 10: **STOP** and run the full vertical-slice review + the Final
Acceptance Test from the brief before expanding the map.

## Later phases (do not start until the slice passes)

3 Systemic survival (injuries, medicine, cooking, spoilage, sleep, weather,
temperature) → 4 Base building → 5 Vehicles → 6 World streaming + zombie
population sim → 7 Long-term survival (farming, fishing, generators, seasons)
→ 8 NPC survivors.

## Tooling

- `scripts/test.sh [unit|integration] [--filter=x]` — headless test suite.
- `scripts/screenshots.sh` — plays the real scene with real input under a
  virtual display and writes evidence to `tests/output/`.
- Docs: `MASTER_PLAN.md` (this), `PROGRESS.md` (per-round log),
  `ARCHITECTURE.md`, `SYSTEMS.md`, `KNOWN_ISSUES.md`.
