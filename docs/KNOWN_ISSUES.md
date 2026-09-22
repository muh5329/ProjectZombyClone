# Known Issues

Ordered by priority. Move fixed items to the bottom section with the round
that fixed them.

## Open

1. **No occlusion handling yet** — camera does not fade roofs/walls. Not a
   bug until buildings exist (Round 2 deliverable).
2. **Player facing indicator is subtle** — the "nose" box on the capsule is
   hard to read at the default zoom. Consider a larger wedge or a ground
   arrow once aiming matters (Round 4).
3. **Mouse aim absent** — brief lists Aim; scheduled with combat (Round 4).
4. **No vault / climb / push** — scheduled with windows (R2) and combat (R4).
5. **HUD is not scaled for high-DPI** — stretch mode is `canvas_items`, so it
   scales with window size, but font sizes are engine defaults.
7. **HUD still polls two things** — the debug overlay (fine) and the
   winded-timer clear (Character does not emit an event when the winded
   lockout expires). Add an `exhaustion_changed` event when needed.
8. **Stamina at 0 while jogging** — the player can keep jogging at 0 %
   stamina (×0.6). Intended for now; revisit with pain/stress (Phase 3).
6. **Screenshot runner is Linux-oriented** — uses `xvfb-run` when present;
   on macOS run `scripts/screenshots.sh` with a display (works, untested
   here).

## Fixed

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
