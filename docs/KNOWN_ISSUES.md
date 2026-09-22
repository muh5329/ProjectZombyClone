# Known Issues

Ordered by priority. Move fixed items to the bottom section with the round
that fixed them.

## Open

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
