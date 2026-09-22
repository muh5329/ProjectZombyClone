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

## Planned (see MASTER_PLAN for order)

Zombie AI ⬜ ·
Sound propagation ⬜ · Combat ⬜ · Health & injuries ⬜ · Inventory ⬜ ·
Loot tables ⬜ · Needs (hunger/thirst/fatigue/temperature) ⬜ ·
Barricades ⬜ · Save/load ⬜ · Crafting ⬜ · World time ⬜ · Vehicles ⬜ ·
Farming ⬜ · Weather ⬜ · Electricity ⬜ · Zombie population sim ⬜ ·
World streaming ⬜ · NPC survivors ⬜
