extends Node
## Global gameplay event bus (autoload: EventBus).
##
## Systems talk to each other through signals here instead of holding direct
## references. Keep signals coarse and gameplay-meaningful. Payloads are plain
## values or Dictionaries so listeners never depend on emitter node types.

# --- Player / character -----------------------------------------------------
## Emitted when any character's movement mode changes (walk/jog/sprint/sneak).
signal movement_mode_changed(character: Node, mode: StringName)
## Emitted when a stat crosses a meaningful threshold (e.g. stamina exhausted).
signal stat_threshold(character: Node, stat: StringName, state: StringName)
## Emitted every time a stat value changes (throttle listeners if needed).
signal stat_changed(character: Node, stat: StringName, value: float, max_value: float)
## Emitted once when a sprint request starts being refused (winded).
signal sprint_denied(character: Node)

# --- Camera -----------------------------------------------------------------
## Emitted when the isometric camera snaps to a new yaw step (degrees).
signal camera_rotated(yaw_degrees: float)
## Emitted when the zoom level index changes.
signal camera_zoomed(level_index: int)

# --- Interaction ------------------------------------------------------------
## The actor's best interactable (or its action list) changed. target may be
## null; actions is the current Array[Dictionary] of {id,label,enabled,reason}.
signal interaction_target_changed(actor: Node, target: Node, actions: Array)
## An action was performed on an Interactable.
signal interaction_performed(actor: Node, target: Node, action_id: StringName)
## An action was refused (disabled, locked, blocked, busy…). reason is text.
signal interaction_refused(actor: Node, target: Node, reason: String)
## Something (a zombie) banged on a door. Recruits nearby zombies via sound.
signal door_banged(door: Node, source: Node)
## A door changed state (&"open" / &"closed" / &"broken").
signal door_state_changed(door: Node, state: StringName)
## A window changed state (&"open" / &"closed" / &"smashed").
signal window_state_changed(window: Node, state: StringName)
## A character finished climbing through a window. hazard = broken glass.
signal window_climbed(actor: Node, window: Node, hazard: bool)

# --- Health -----------------------------------------------------------------
## A character took damage. info: {region: StringName, ...} (free-form).
signal character_damaged(character: Node, amount: float, source: Node, info: Dictionary)
## A character's health reached 0.
signal character_died(character: Node, source: Node)
## Slow health loss that is not a hit (bleeding, infection, starvation,
## thirst, food poisoning): cause &"bleeding" / &"infection" / &"needs".
## Not a character_damaged: it does not interrupt actions (Round 7).
signal health_drained(character: Node, amount: float, cause: StringName)
## Any change of a character's health (damage, bleeding, infection, heal).
signal health_changed(character: Node, value: float, max_value: float)

# --- Injuries (Round 4) -----------------------------------------------------
## The injury list changed (added, bandaged, stopped bleeding, healed).
## summary: Array of Injury.to_dict() ({region, type, label, bleeding,
## bandaged, infected, ...}), worst first.
signal injuries_changed(character: Node, summary: Array)
## Bandaging started / finished on [region] (StringName id).
signal bandage_started(character: Node, region: StringName, seconds: float)
signal bandage_finished(character: Node, region: StringName)
## Bandaging was cut short (the character got hurt).
signal bandage_interrupted(character: Node, region: StringName)
## Visible infection stage changed: &"none" (hidden), &"feverish", &"infected".
signal infection_stage_changed(character: Node, stage: StringName)
## A makeshift dressing (rag) gave way: the wound on [region] bleeds again.
signal wound_reopened(character: Node, region: StringName)
## Blood hit the ground (decals). amount 0..1.
signal blood_spilled(position: Vector3, amount: float)

# --- Combat (Round 4) -------------------------------------------------------
## A swing / shove started (stamina already paid). weapon_id e.g. &"baseball_bat", &"shove".
signal melee_swing(actor: Node, weapon_id: StringName, charge: float)
## A swing connected. info: {region, knockback_dir, knockback, knockdown, crit, weapon}.
signal melee_hit(actor: Node, target: Node, damage: float, info: Dictionary)
## An attack / shove was refused (reason is player-facing text).
signal attack_refused(actor: Node, reason: String)
## Aim mode toggled or the number of targets within reach changed.
signal melee_aim_changed(actor: Node, aiming: bool, in_reach: int)
## item: {id, name, condition, max_condition} (fists: id &"fists", max_condition 0).
signal weapon_equipped(actor: Node, item: Dictionary)
signal weapon_condition_changed(actor: Node, item: Dictionary)
signal weapon_broken(actor: Node, item: Dictionary)
## A world item was picked up. item: {id, name}.
signal item_picked_up(actor: Node, item: Dictionary)

# --- Inventory / containers (Round 5) ----------------------------------------
## An ItemContainer's contents changed. owner = the node exposing it as
## `inventory` (the player, a LootContainer, a corpse).
signal inventory_changed(owner: Node)
## [actor] opened / closed [container] (a LootContainer). The loot window
## listens; the HUD never needs to know about containers.
signal container_opened(actor: Node, container: Node)
signal container_closed(actor: Node, container: Node)
## Items moved between two inventory owners. item: {id, name, count}
## (id &"" for a bulk "Loot All" / "Transfer All").
signal item_transferred(from: Node, to: Node, item: Dictionary)
## A generic timed action ("Rummaging…") started / ended on [actor]
## (busy for [seconds]). The HUD shows a progress bar + label.
signal timed_action_started(actor: Node, action: StringName, label: String, seconds: float)
signal timed_action_finished(actor: Node, action: StringName, completed: bool)

# --- Equipment / encumbrance (Round 6) -------------------------------------
## An Equipment slot changed. slot: &"primary_hand" / &"secondary_hand" /
## &"back". item: {id, name} ({} when emptied).
signal equipment_changed(character: Node, slot: StringName, item: Dictionary)
## The quick-equip hotbar changed (assignments or which one is equipped).
## slots: [{index, id, name, color, equipped, carried}] ({index} when empty).
signal hotbar_changed(character: Node, slots: Array)
## Carried weight or encumbrance state changed. state: &"ok" / &"light" /
## &"heavy" / &"overloaded"; weight in kg (worn-bag reduction applied).
signal encumbrance_changed(character: Node, state: StringName, weight: float)
## The inventory / loot screen was shown or hidden (clicks on the world
## do not attack while it is open).
signal inventory_screen_toggled(visible: bool)
## An item was dropped to the ground. item: {id, name, count}.
signal item_dropped(character: Node, item: Dictionary)

# --- World time (Round 7) ----------------------------------------------------
## Game time moved from [from_minute] to [to_minute] (game minutes since the
## world start; every physics tick while time runs, once per advance()).
signal time_advanced(from_minute: float, to_minute: float)
## A whole game minute / hour / day went by (absolute minute, hour of day
## 0..23 + day index, day index since the start).
signal minute_passed(total_minute: int)
signal hour_passed(hour: int, day: int)
signal day_passed(day: int)
## Speed step changed: 0 paused, 1 = 1×, 2 = 2×, 3 = 4× (scale = Engine.time_scale).
signal time_speed_changed(step: int, scale: float)

# --- Survival needs (Round 7) ------------------------------------------------
## A need's severity level changed. need: &"hunger" / &"thirst" / &"fatigue"
## / &"sickness"; level 0 (fine) .. 4; label e.g. "Hungry" ("" at level 0).
signal need_level_changed(character: Node, need: StringName, level: int, label: String)
## The visible moodles changed: [{id, label, level, max_level}] worst first.
signal moodles_changed(character: Node, moodles: Array)
## Something was eaten / drunk. item: {id, name, portion, hunger, thirst,
## sickness, spoil_state}.
signal item_consumed(character: Node, item: Dictionary)
## Sleep / rest began or ended. reason: "" (woke rested), "Woken by noise!",
## "Woken: under attack!", "Got up" …
signal sleep_started(character: Node, bed: Node)
signal sleep_ended(character: Node, reason: String)
signal rest_started(character: Node, seat: Node)
signal rest_ended(character: Node, reason: String)

# --- Sound (Round 8: SoundManager emits this for every gameplay sound) ------
## Something made a noise. radius in metres (before attenuation), intensity
## 0..1, category = a SoundCategory id (&"footstep_jog", &"window_smash"…).
## source may be null. Emitted by SoundManager.emit_sound() — never emit it
## directly (zombies listen through SoundManager, not this signal).
signal sound_emitted(position: Vector3, radius: float, intensity: float, category: StringName, source: Node)
## The player shouted (H). ok = false with a reason when refused.
signal shouted(character: Node, ok: bool, reason: String)
## A floor hazard hurt a character (hazard &"glass"; region id).
signal hazard_hurt(character: Node, hazard: StringName, region: StringName)

# --- Zombies ----------------------------------------------------------------
signal zombie_state_changed(zombie: Node, from: StringName, to: StringName)
signal zombie_spotted_target(zombie: Node, target: Node)
signal zombie_lost_target(zombie: Node)
## hit = false when the swing missed (target moved away / not facing).
signal zombie_attacked(zombie: Node, target: Node, hit: bool)
signal zombie_died(zombie: Node, killer: Node)
## A zombie was knocked to the ground / got back up.
signal zombie_knocked_down(zombie: Node, source: Node)
signal zombie_got_up(zombie: Node)

# --- Barricades / carpentry (Round 9) -----------------------------------------
## The plank count on a door / window changed (nailed, pried off, broken).
signal barricade_changed(fixture: Node, planks: int)
## A zombie (or anything) broke a plank off [fixture].
signal barricade_plank_broken(fixture: Node, source: Node)
## Furniture was pushed in front of / away from a door (door null = back).
signal furniture_moved(furniture: Node, door: Node)
## A piece of furniture was destroyed (zombies) or taken apart (player).
signal furniture_destroyed(furniture: Node, source: Node)
## Skills (SkillComponent): XP gained / a new level reached.
signal skill_xp_gained(character: Node, skill: StringName, xp: float)
signal skill_leveled(character: Node, skill: StringName, level: int)

# --- Buildings / location ---------------------------------------------------
## The player entered a Room (or left all rooms: room == null).
signal player_room_changed(room: Node, building: Node)

# --- World / debug ----------------------------------------------------------
## Free-form debug message for the on-screen log (dev only).
signal debug_message(text: String)


func debug(text: String) -> void:
	debug_message.emit(text)
