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

## Camera ✅ (Round 1)

- Elevated isometric rig, 8 headings (Q/R), 4 zoom levels (wheel, +/−),
  smooth follow. Occlusion (roof/wall fading) ⬜ Round 2.

## HUD 🔶 (Round 1)

- Movement mode + stamina bar (green / orange <25 % / red exhausted, flashes
  on exhaustion), debug overlay (F3), key hints. Will grow per round; each
  system adds its own widget rather than the HUD knowing about systems.

## Planned (see MASTER_PLAN for order)

Interaction framework ⬜ · Buildings/doors/windows ⬜ · Zombie AI ⬜ ·
Sound propagation ⬜ · Combat ⬜ · Health & injuries ⬜ · Inventory ⬜ ·
Loot tables ⬜ · Needs (hunger/thirst/fatigue/temperature) ⬜ ·
Barricades ⬜ · Save/load ⬜ · Crafting ⬜ · World time ⬜ · Vehicles ⬜ ·
Farming ⬜ · Weather ⬜ · Electricity ⬜ · Zombie population sim ⬜ ·
World streaming ⬜ · NPC survivors ⬜
