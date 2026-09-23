# Known Issues

Ordered by priority. Move fixed items to the bottom section with the round
that fixed them.

## Open

000000. **Round-8 sound / hearing gaps** (ordered):
   - **Obstacles are counted, not measured**: up to 5 per ray; a thick
     wall and a thin one weigh the same. The per-event cache is keyed by
     a 1.5 m ear cell, so two ears in one cell on either side of a wall
     share a result.
   - **Openings**: only exterior openings; interior doorways use the
     direct ray only. Building → building assumes the leg between the two
     openings is clear. One opening per building leg (no chains).
   - **One hash refresh per 0.2 s**: listeners moving > 2 m between
     refreshes could be missed at the query edge (zombies move ≤ 0.35 m).
   - **Dispatch is synchronous**: a sound is evaluated once when emitted
     (no duration-long "still audible" window); `duration` only drives
     debug rings. Alarms / generators (future) will need re-emission.
     Queued sounds (moans) are delayed ≤ a few frames.
   - **Moan relays** can walk a crowd across the map in a dense
     population (2 hops × 6 m + each zombie's own hearing); tuned only
     against the 10-zombie map and the 200-zombie perf run.
   - **No shoes exist yet**, so every survivor is "barefoot" on glass
     (`Player.has_foot_protection()` looks for an equipped `shoes` tag).
     Zombies and NPCs ignore glass; walking on glass makes no sound.
   - **Rings are shown for every player sound**, footsteps included
     (alpha by intensity); PZ only rings deliberate / loud noises.
   - **Sleep wake** checks zombie line of sight from the zombie's eye
     to the sleeper's eye only (one ray each, 4 Hz).

00000. **Round-7 time / needs / food / sleep gaps** (ordered):
   - **Injury timers are physics seconds, not game minutes** (1:1 only at
     the default rate). 2× / 4× speed them up with the engine; during a
     sleep RestComponent feeds wounds the skipped game time (and sleep is
     refused while bleeding). Changing `minutes_per_second` would need
     the injury numbers retuned.
   - **Zombies are still under-simulated while you sleep**: Engine ×8
     gives 192 s of zombie time for an 8 h night (vs 8 h of game time).
     Big steps (0.13 s) at ×8 are fine for shambling; a population sim
     would do the rest. Sleep wakes on a zombie within 10 m (not 8: an
     investigating zombie stops ~1 m short of the door).
   - **Temperature is display only** (no body temperature, clothing,
     weather); wetness / stress / pain-as-need are not needs yet.
   - **Pause freezes the HUD** (SceneTree.paused): notices do not fade and
     the inventory cannot be used while paused.
   - **Interrupted eating consumes nothing** (PZ gives a partial portion).
     Walking off also interrupts (move intent while busy).
   - **Fast-forward only checks chasing zombies**, not idle ones next to
     you; sleep checks both (15 m).
   - **Moodles are coloured circles with an initial**, no icon art; the
     tooltip needs the mouse over the row.
   - **Power is always on** (fridges always cold) until the electricity
     round; the water shuts off on `water_shutoff_day` (14), there is no
     rain collection yet.
   - **The sleeper does not lie on the bed** (stands next to it, screen
     faded); sleeping anywhere but a bed (floor, sofa) is not possible.
   - **Stale and fresh stacks never merge; a merged stack keeps the older
     age** (no per-item ages inside a stack). Spoil-state changes do not
     refresh an open inventory list until it changes / reopens.
   - **Interior lights are shadowed spotlights** (one per room, 5 in House
     A): fine now, but a whole town at night will need a light budget /
     distance culling. Window glow is emission only (no light cast
     outside).
   - **Food balance is per House A only** (kitchen tables); no pantry /
     living-room food, store and warehouse tables are untuned.
0000. **Round-6 inventory / equipment gaps** (ordered):
   - **Only the worn bag and bags on the ground are accessible**: a bag
     carried inside the main inventory (or in a container) is a closed,
     full-weight item — no tab for it. Deliberate (keeps every capacity
     invariant), but PZ lets you open any carried bag.
   - **Dropped items are not persisted**: they are children of the map
     (they stay for the session), but not registered in `WorldState`;
     Round 10 must add them (and the player's `carried_to_dict`) to the
     save.
   - **No attacking while the inventory screen is open** (by design since
     the Round-6 critic); shove (Space) still works.
   - **Clothing is not wearable** yet (t-shirt / jacket / socks have no
     slots); only hands + back exist. No belt / holster slots.
   - **Encumbrance thresholds are fixed numbers** in the profile (8 / 12 /
     15 kg), not strength / traits based; swing stamina costs are not
     scaled by load (only per-second drains are).
   - **Rows are not zebra-striped** (a removal would re-style every row
     below it); refresh cost is ~7 ms for 400 rows on the dev box, of
     which most is building row data, not nodes.
   - **Hotbar is keys only**: slots are not clickable and cannot be
     dragged onto; assignment is via the context menu.
   - **Identical non-stackables still take one row each** (no "×2
     (expand)" grouping).
   - The context menu is a Godot `PopupMenu` (keyboard focus while open;
     clicking outside closes it).
000. **Round-5 containers / loot gaps** (ordered):
   - **Loot window is laid out for 1280×720** (x 150–930, left of the
     body panel); not scaled for other resolutions; a very long list
     scrolls (max 264 px).
   - **Rummage noise is a flat 3 m** `rummage` sound for every container
     (the container's `search_noise_radius`); corpses are silent.
   - **Containers do not respawn / refill**; world age only thins the
     first roll. No per-building "already looted" state for AI survivors.
   - **Furniture blocks windows only by placement** (the plan validator
     checks the room rect, not overlaps with doors / windows / other
     pieces).
   - **Save / load** only has `to_dict/from_dict` + `WorldState`
     snapshots; nothing writes them to disk until Round 10.
00. **Round-4 combat / injury gaps** (ordered):
   - **Knocked-down zombies keep their upright capsule**: only the visual
     lies down, so the player bumps into an invisible standing body over
     the lying mesh. (Swings still find it: the target query is a sphere.)
   - **Targets are resolved once, at the start of the active window**; a
     zombie stepping into the arc mid-window is not hit. No per-frame
     sweep.
   - **No animations / hit reactions**: the weapon is a box that sweeps
     through the arc; bites do not stagger the player; the zombie hit
     reaction is a 0.2 s red body flash + knockback.
   - **Arc / ring are depth-tested ground meshes**: hidden under zombie
     bodies and indoors under the cutaway rules; readable in the open.
   - No disinfectant / stitches / splint *use* yet (the items exist as
     data; B refuses fractures). Burns and
     fractures exist as data but nothing inflicts them yet.
   - **Smashed-window climbs always lacerate** (`glass_laceration_chance`
     1.0) — there is no "clear glass" action yet.
   - **Infection stages are cosmetic** (Feverish ≥ 25, Infected ≥ 60): no
     fever effects yet until the lethal drain at 100. Hand wounds do not
     affect combat.
   - **Max-stamina reduction clamps the current value**: a swing paid
     just before a wound lowers the cap can look free (HUD shows stamina
     against the base max with "(max N%)").
   - **Mouse aim intersects the plane at the player's feet**; multi-level
     buildings will need a ground raycast.
   - **Balance is tuned against one bot** (stand still, 0.35 s charges,
     shove windups): 1v1 bat ≈ 23 % health, 3 zombies always kill it. A
     player who backs off between swings does much better; no footwork
     in the bot.
   - **Attack-slot registry** is still static, but slots are now released
     when a zombie leaves the tree (was: a despawned attacker kept the
     target "full" forever).
   - **Condition only wears on swings that connect**; misses are free.
   - **Test suite runtime** is ~210 s (watchdog 600 s); each integration
     test bakes the navmesh.
   - The screenshot run disables the three staging zombies' senses until
     shot 14 is taken (so the aim ring / arc read clearly).
0. **Zombie Round-3 gaps** (ordered):
   - **Cheap-mode zombies are out of the physics space** (calm and known
     to be > 8 m from the player): they overlap each other and are not
     seen by `Door._blocked_at` (a door can swing into one) or by shape
     queries. They regain a body within one sense check of the player
     coming within 8 m, of turning hostile, or of any hit.
   - **Zombies never open doors and only bang on a breakable that is
     *ahead on their path*** (1.2 m ray at 2 Hz); a door hit from the
     side or a zombie pushed against a door by the crowd just stands
     (stuck timer → idle / search). No window climbing, no vaulting.
   - **Player is the only prey**; `zombie.target` is duck-typed so NPCs
     can join through a group later.
   - **Attack tell is minimal**: lunge + white head flash; no swing
     animation, no player hit reaction (Round 4).
   - **Perf budget is machine-bound**: ≈ 5 ms calm / ≈ 8.5 ms hostile per
     physics step with 200 zombies on the (slow, 2-core) dev box against
     8 / 10 ms budgets. Next step: a zombie manager ticking far zombies
     at 5 Hz or turning them into pure data (population sim).
   - **Attack slots are a static registry** keyed by target instance id
     (`ZombieAI._attack_slots`); a target freed while attacked is pruned
     only when its attackers release.
   - **Navmesh y is ~0.2 m above the floor** (Recast voxel rounding);
     all path use ignores Y. Prop tops (car roof) bake as walkable
     islands; the spawner rejects points above 0.75 m.
   - **The map's 10 seeded zombies roam during the Round-2 screenshot
     section** (seed 1337 is verified stable; a different seed may put a
     zombie in the door arc → "Blocked").
   - **Restart (R) reloads the whole scene**; no death cause / stats.
1. **Cutaway is facade-wide, not view-based** — every camera-facing
   exterior wall of the building is stubbed, even in rooms the player is
   not in; interior partitions are only cut for the current room. Good
   enough for one-storey houses; multi-storey / large buildings will need a
   per-room or per-ray rule.
2. **Single occlusion ray** — outside, only a ray to the player's centre
   is tested, so a prop covering just the head/feet is not faded.
3. **Door blocking checks only the end position** — the leaf's arc is not
   swept, so a character standing mid-arc (not at the target) can still be
   nudged by the moving StaticBody.
4. **Climb does not check the landing spot** — the tween lands 0.9 m past
   the wall regardless of props there.
5. **Smash needs no tool and no strength check** — placeholder until items
   (R5); the equipped weapon is not consulted yet.
6. **Interior door lintels are cut with the wall** — cosmetic: the stub of
   a door leaf reads a little odd while the door is open.
7. **Faded objects keep casting full shadows** — alpha fade does not affect
   shadow maps; a hidden roof stops shadows only once fully hidden.
8. **Player facing indicator is subtle** — the "nose" box on the capsule is
   hard to read at the default zoom; while aiming the ring + arc preview
   show the direction, otherwise only the held weapon does.
10. **No vault over low obstacles** — window climb exists (R2), shove
   exists (R4); fences / vaulting later.
11. **HUD is not scaled for high-DPI** — stretch mode is `canvas_items`, so it
   scales with window size, but font sizes are engine defaults.
12. **HUD still polls two things** — the debug overlay (fine) and the
   winded-timer clear (Character does not emit an event when the winded
   lockout expires). Add an `exhaustion_changed` event when needed.
13. **Stamina at 0 while jogging** — the player can keep jogging at 0 %
   stamina (×0.6). Intended for now; revisit with pain/stress (Phase 3).
14. **Screenshot runner is Linux-oriented** — uses `xvfb-run` when present;
   on macOS run `scripts/screenshots.sh` with a display (works, untested
   here).

## Fixed

- (R8, critic) Two-ray attenuation undercounted walls and let furniture
  hide walls → iterative ray; door / window sounds started inside the
  leaf → 0.3 m actor-side offset + hit_from_inside; non-finite sounds
  rejected; expiry scans the whole list; openings work inward and
  building → building; moan re-targets never downgrade; dead players
  get no shout notice / meter; one LOUD threshold in data; sleep wakes
  through the sound system + zombie line of sight; occlusion loops no
  longer crash on freed meshes.
- (R8) Hearing occlusion was one ray halving the radius for any number
  of walls → SoundManager propagation (per-obstacle factors, openings,
  spatial hash).
- (R5, critic) Equipped weapon could be stored mid-swing →
  `Player.can_release_item` checked by every outgoing transfer.
- (R5, critic) `remove(item, 0)` removed one; `from_dict` accepted
  counts ≤ 0 and over-capacity loads; one instance could sit in two
  containers (weak owner back-ref now).
- (R5, critic) World age could reshuffle later rolls (gate consumed the
  shared rng); per-roll sub-rng.
- (R5, critic) Loot rows bound to list indices (double press moved two
  stacks); rows now bind to the ItemInstance and are pooled.
- (R5, critic) Corpse ids from `ai_seed` collided for two spawners on
  one seed; spawner path + monotonic counter.
- (R5, critic) An interrupted bandage with a full pack lost the dressing
  (now dropped at the feet); a wound that vanished mid-bandage ate it
  (refunded).
- (R5, critic) Loot too generous; retuned for scarcity (see SYSTEMS).
- (R5, critic) Loot window hid the room label; label moved bottom-left.

- (R5) Bandages were free and unlimited; B now consumes a bandage / rag
  from the inventory and refuses "No bandages".
- (R5) "Search corpse" was a disabled placeholder; corpses are loot
  containers.
- (R5) `Player.held_items` stopgap replaced by `Player.inventory`
  (ItemContainer, 15 kg).

- (R4, critic) Interrupted swings (busy / death) kept their queued
  follow-up → double swing + double stamina later; the queue is cleared by
  every finish.
- (R4, critic) Swapping weapons mid-swing dodged wear; wear goes to the
  swung instance and X is refused mid-swing.
- (R4, critic) A knockdown cancelled its own knockback.
- (R4, critic) Blood decals ignored the floor height (y from the hit).
- (R4, critic) Bat stun-lock made 1v1 free (0 % health): stagger 16,
  0.5 s, 1.2 s immunity, faster/longer bite, weaker bat knockback.
- (R4, critic) Zombie head stayed hit-coloured / corpse body stayed red
  after a killing blow; the hit flash now restores the state tint and
  collapse clears it.
- (R4) Mouse aim (RMB) added: ortho-safe mouse → ground projection,
  facing override, walk cap, ring at reach.
- (R4) Zombie attack always passed `region: random, type: bite`; bites
  now roll region + type from the profile and wound the victim.
- (R4) HUD stamina percentage hid the injury cap (value / reduced max
  read 100 %); now shown against the base max with "(max N%)".

- (R3) Door leaves were on layer 1 and got baked into the navmesh (no
  path into houses). New layer 7 "doors"; player/zombie masks include it.
- (R3) `NavigationServer3D` map queries returned nothing right after
  `bake_finished`; `NavBaker` now waits for the map iteration id to advance.
- (R3) Recast rounds agent radius/height to cell multiples (0.35 → 0.5
  with cell 0.25 blocked 0.9 m doorways); cell 0.15, radius 0.3, height 1.5.
- (R3) Children `_ready` before the parent's `@onready` vars: AI/Senses are
  wired by `Zombie._ready()` through explicit `setup()`.
- (R3) Chase copied the *live* target position while `visible_target` was
  stale between 6 Hz checks (a teleported player leaked its new position);
  last-known now comes from the senses' snapshot.
- (R3) `wait_until` (process frames) timed out long before gameplay
  timers elapsed headless; added `wait_physics_until`.
- (R3) `StateMachine` ↔ `AIState` strong cycle leaked RefCounted objects
  at exit; the state's back-reference is a `WeakRef`.
- (R3) Perf probe counted the post-spawn catch-up burst as 50 ms frames;
  it now samples once per main-loop iteration after a warm-up.
- (R3) Physics engine switched to Jolt (200 kinematic bodies were ~1.5 ms
  cheaper per step and CharacterBody3D behaviour is unchanged in the tests).
- (R3, critic) `die()` set `dead` before clearing `cheap_movement`, whose
  setter bailed out on `dead` → corpses never re-entered the physics
  space. Death now hands over to a separate `ZombieCorpse`.
- (R3, critic) Bites through walls (attack range > capsule radii + wall):
  entering Attack, every swing and proximity detection need a clear
  chest-to-chest ray.
- (R3, critic) Broken doors were untargetable (shape disabled); the body
  stays on layer 4 only.
- (R3, critic) HUD chase count went stale when a chasing zombie was freed
  without dying; pruned on `tree_exiting` and every frame.
- (R3, critic) Vision through windows: glass is now its own body on layer
  8, dropped when open / smashed.
- (R3, critic) `sound_emitted` crashed when the source was freed before a
  listener ran ("Cannot convert argument"); the listener takes a Variant.
- (R3, critic) Tick phases came from instance ids (non-deterministic);
  now from the seeded `ai_seed`.
- (R3, critic) `Door._blocked_at` allocated a query + shape per physics
  tick while targeted; cached.
- (R3, critic) `Performance.TIME_PHYSICS_PROCESS` refreshes at 1 Hz — the
  perf probe now measures each step itself.
- (R3, critic) Static Resource caches (`_head_materials`, `_shared_mesh`)
  were reported as leaks at exit; moved to a tree-owned `ZombieAssets`.

- (R2) `Area3D.get_overlapping_bodies()` never reported the static door /
  window bodies in headless runs; `PlayerInteraction` now uses a direct
  `intersect_shape` query each physics tick (deterministic, no overlap
  bookkeeping).
- (R2) `class_name Window` collides with Godot's built-in `Window`; the
  class is `HouseWindow` (file stays `interaction/window.gd`).
- (R2) Trees in `test_ground.tscn` stood inside the new house footprint;
  moved.
- (R2) Occlusion: `MeshInstance3D.transparency` is a no-op in the
  Compatibility renderer (verified: the player vanished behind faded
  walls); fading uses a per-instance `material_override` duplicated from
  the mesh's material, so shared materials are never mutated.
- (R2, critic) Window climb tween was bound to the window: freeing it
  mid-climb left the player busy forever. The actor now owns the tween.
- (R2, critic) Interactables were targetable through walls; LOS ray added.
- (R2, critic) Room detection flickered on thresholds; hysteresis added.
- (R2, critic) Doors could swing into characters; blocked check + cooldown.

- (R1, critic) Sub-epsilon stat changes swallowed by `is_equal_approx`.
- (R1, critic) Empty `zoom_levels` / zero `yaw_step_degrees` crashed camera.
- (R1, critic) Player lost registration on re-parent (now `_enter_tree`).
- (R1, critic) Camera errored when target left the tree.
- (R1, critic) Sprint drain ignored effort (wall / partial stick paid full).
- (R1, critic) Exhaustion duplicated between Character and StatsComponent.
- (R1, critic) HUD polled Character; now EventBus-driven.
- (R1, critic) Camera tests depended on wall-clock; now `wait_until`.
- (R1, critic) Runner ignored parse errors / SCRIPT ERROR; now fails.

- (R1) `Input.action_press()` does not dispatch to `_unhandled_input`; the
  screenshot runner now uses `Input.parse_input_event(InputEventAction)`.
- (R1) `-s` runner scripts compiled before autoloads existed → avoid static
  typing against gameplay classes inside SceneTree scripts.
- (R1) Screenshot runner waited on render frames; under software rendering
  physics catches up so 90 frames ≈ 7 s. Now waits on physics frames.
- (R1) Hand-typed non-orthonormal `DirectionalLight3D` transform blew out
  lighting; replaced with `rotation_degrees`.
- (R1) `ext_resource` after `sub_resource` in a hand-written `.tscn` fails to
  parse; keep all ext_resources first.
