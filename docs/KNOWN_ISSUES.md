# Known Issues

Ordered by priority. Move fixed items to the bottom section with the round
that fixed them.

## Open

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
   - **Hearing occlusion is one ray**: a wall halves the radius, whatever
     its thickness or count. Round 8.
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
   - **Search corpse** is a disabled placeholder until inventory (R5).
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
   (R5) and combat (R4).
6. **Interior door lintels are cut with the wall** — cosmetic: the stub of
   a door leaf reads a little odd while the door is open.
7. **Faded objects keep casting full shadows** — alpha fade does not affect
   shadow maps; a hidden roof stops shadows only once fully hidden.
8. **Player facing indicator is subtle** — the "nose" box on the capsule is
   hard to read at the default zoom. Consider a larger wedge or a ground
   arrow once aiming matters (Round 4).
9. **Mouse aim absent** — brief lists Aim; scheduled with combat (Round 4).
10. **No vault over low obstacles / push** — window climb exists (R2);
   fences and shoving come with combat (R4).
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
