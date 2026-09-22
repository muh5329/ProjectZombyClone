extends CanvasLayer
## Minimal survival HUD. Event-driven: listens to the EventBus for the
## registered player's stats and movement mode. Only the debug overlay
## polls (position/speed/fps are not events).
## Deliberately dumb: no gameplay logic, only presentation.

const COL_OK := Color(0.55, 0.8, 0.35)
const COL_LOW := Color(0.95, 0.65, 0.2)
## Exhausted is orange-red so the stamina bar never matches the health bar.
const COL_EXHAUSTED := Color(0.95, 0.45, 0.2)
const COL_HEALTH := Color(0.6, 0.08, 0.06)
const COL_FEVER := Color(1.0, 0.6, 0.2)
const COL_INFECTED := Color(1.0, 0.25, 0.2)

@onready var health_bar: ProgressBar = %HealthBar
@onready var health_label: Label = %HealthLabel
@onready var danger_label: Label = %DangerLabel
@onready var damage_flash: ColorRect = %DamageFlash
@onready var death_overlay: ColorRect = %DeathOverlay
@onready var stamina_bar: ProgressBar = %StaminaBar
@onready var stamina_label: Label = %StaminaLabel
@onready var mode_label: Label = %ModeLabel
@onready var debug_label: Label = %DebugLabel
@onready var hint_label: Label = %HintLabel
@onready var notice_label: Label = %NoticeLabel
@onready var prompt_label: Label = %PromptLabel
@onready var room_label: Label = %RoomLabel
@onready var weapon_label: Label = %WeaponLabel
@onready var condition_bar: ProgressBar = %ConditionBar
@onready var pain_label: Label = %PainLabel
@onready var infected_label: Label = %InfectedLabel
@onready var injury_label: Label = %InjuryLabel
@onready var aim_label: Label = %AimLabel
@onready var charge_bar: ProgressBar = %ChargeBar
@onready var bandage_bar: ProgressBar = %BandageBar

var _flash_time: float = 0.0
var _notice_time: float = 0.0
var _stamina_state: StringName = &"normal"
var _mode: StringName = &"jog"
var _exhausted: bool = false
var _frac: float = 1.0
## Current max stamina as a fraction of the profile's base (wounds lower it).
var _stamina_cap: float = 1.0
var _health_frac: float = 1.0
## Zombies currently chasing / attacking the player (zombie -> true).
var _chasers: Dictionary = {}
var _flash_tween: Tween
var _dead: bool = false
var _injury_summary: Array = []
var _infection_stage: StringName = &"none"
## Player stands still (mode label reads "Idle").
var _idle: bool = true


func _ready() -> void:
	EventBus.stat_changed.connect(_on_stat_changed)
	EventBus.stat_threshold.connect(_on_stat_threshold)
	EventBus.movement_mode_changed.connect(_on_mode_changed)
	EventBus.sprint_denied.connect(_on_sprint_denied)
	EventBus.interaction_target_changed.connect(_on_interaction_target_changed)
	EventBus.interaction_refused.connect(_on_interaction_refused)
	EventBus.player_room_changed.connect(_on_player_room_changed)
	EventBus.character_damaged.connect(_on_character_damaged)
	EventBus.character_died.connect(_on_character_died)
	EventBus.zombie_state_changed.connect(_on_zombie_state_changed)
	EventBus.zombie_died.connect(_on_zombie_died)
	EventBus.health_changed.connect(_on_health_changed)
	EventBus.injuries_changed.connect(_on_injuries_changed)
	EventBus.bandage_started.connect(_on_bandage_started)
	EventBus.bandage_finished.connect(_on_bandage_finished)
	EventBus.attack_refused.connect(_on_attack_refused)
	EventBus.melee_aim_changed.connect(_on_aim_changed)
	EventBus.weapon_equipped.connect(_on_weapon_changed)
	EventBus.weapon_condition_changed.connect(_on_weapon_changed)
	EventBus.weapon_broken.connect(_on_weapon_broken)
	EventBus.item_picked_up.connect(_on_item_picked_up)
	EventBus.bandage_interrupted.connect(_on_bandage_interrupted)
	EventBus.infection_stage_changed.connect(_on_infection_stage_changed)
	charge_bar.visible = false
	bandage_bar.visible = false
	danger_label.text = ""
	death_overlay.visible = false
	health_bar.modulate = COL_HEALTH
	health_label.add_theme_color_override(&"font_color", Color.WHITE)
	_set_flash(0.0)
	hint_label.text = "WASD move · Shift sprint · Ctrl sneak · Alt walk · E interact · 1-4 actions · LMB attack (hold: charge) · RMB aim · Space shove · X weapon · B bandage · Q/R rotate · Wheel zoom · F3 debug"
	aim_label.text = ""
	_on_weapon_changed(GameManager.player, {"name": "Fists", "max_condition": 0})
	_refresh_body()
	notice_label.text = ""
	prompt_label.text = ""
	room_label.text = ""
	_sync_from_player()
	_refresh()


func _is_player(c: Node) -> bool:
	return c != null and c == GameManager.player


## Base max stamina (percentages are of this, so wounds show as a lower cap).
func _stamina_base() -> float:
	var p := GameManager.player as Character
	return p.profile.stamina_max if p and p.profile else 100.0


## Pull current values once (HUD may be created after the player).
func _sync_from_player() -> void:
	var p := GameManager.player as Character
	if p == null:
		return
	_frac = p.stats.get_fraction(Character.STAMINA)
	_stamina_state = p.stats.get_state(Character.STAMINA)
	_mode = MovementComponent.mode_name(p.effective_mode)
	_exhausted = p.exhausted
	if p.health:
		_health_frac = p.health.fraction()
		_dead = p.health.dead


func _on_stat_changed(c: Node, stat: StringName, value: float, max_value: float) -> void:
	if not _is_player(c):
		return
	if stat == Character.STAMINA:
		var base := _stamina_base()
		_frac = 0.0 if base <= 0.0 else value / base
		_stamina_cap = 1.0 if base <= 0.0 else max_value / base
		_refresh()
	elif stat == InjuryComponent.PAIN:
		pain_label.text = format_pain(value, max_value)


func _on_stat_threshold(c: Node, stat: StringName, state: StringName) -> void:
	if stat != Character.STAMINA or not _is_player(c):
		return
	_stamina_state = state
	_exhausted = (c as Character).exhausted
	if state == &"exhausted":
		_flash_time = 1.2
		_notice("Exhausted!", 2.0)
	_refresh()


func _on_mode_changed(c: Node, mode: StringName) -> void:
	if _is_player(c):
		_mode = mode
		_exhausted = (c as Character).exhausted
		_refresh()


func _on_sprint_denied(c: Node) -> void:
	if _is_player(c):
		_notice("Too winded to sprint", 1.5)


func _on_interaction_target_changed(actor: Node, target: Node, actions: Array) -> void:
	if not _is_player(actor):
		return
	if target == null:
		prompt_label.text = ""
		return
	var target_name := String(target.call("display_name")) if target.has_method("display_name") else ""
	prompt_label.text = format_prompt(target_name, actions)
	var any_enabled := false
	for a in actions:
		if bool(a.get("enabled", true)):
			any_enabled = true
	prompt_label.modulate = Color.WHITE if any_enabled else Color(0.7, 0.7, 0.7, 0.85)


func _on_interaction_refused(actor: Node, _target: Node, reason: String) -> void:
	if _is_player(actor):
		_notice(reason, 1.5)


## Pure formatter. Enabled: "E: Open door   [2] Smash window"; disabled
## actions are greyed via BBCode-free brackets: "[3] Climb through (Window is closed)".
## (Label has no rich text; the parenthesised reason is the greying.)
static func format_prompt(target_name: String, actions: Array) -> String:
	if actions.is_empty():
		return target_name
	var parts: PackedStringArray = []
	var primary_done := false
	for i in actions.size():
		var a: Dictionary = actions[i]
		var label := String(a.get("label", ""))
		var enabled := bool(a.get("enabled", true))
		var reason := String(a.get("reason", ""))
		var key := ""
		if enabled and not primary_done:
			key = "E"
			primary_done = true
		elif i < 4:
			key = "[%d]" % (i + 1)
		else:
			continue
		if not enabled:
			parts.append("%s %s (%s)" % [key, label, reason if reason != "" else "unavailable"])
		else:
			parts.append("%s: %s" % [key, label] if key == "E" else "%s %s" % [key, label])
	return "   ".join(parts)


func _on_player_room_changed(room: Node, building: Node) -> void:
	if room == null:
		room_label.text = ""
		return
	var rn := String(room.get("room_name")) if "room_name" in room else String(room.name)
	var bn := String(building.get("display_name")) if building != null and "display_name" in building else ""
	room_label.text = "Inside: %s%s" % [rn, (" — " + bn) if bn != "" else ""]


# --- Health / zombies -------------------------------------------------------

func _on_health_changed(c: Node, value: float, max_value: float) -> void:
	if not _is_player(c):
		return
	_health_frac = 0.0 if max_value <= 0.0 else clampf(value / max_value, 0.0, 1.0)
	_refresh()


# --- Injuries / combat (Round 4) -----------------------------------------------

func _on_injuries_changed(c: Node, summary: Array) -> void:
	if not _is_player(c):
		return
	_injury_summary = summary
	_refresh_body()


func _refresh_body() -> void:
	injury_label.text = format_injuries(_injury_summary)
	# The infection stays hidden until symptoms show (never "green").
	infected_label.visible = _infection_stage != &"none"
	infected_label.text = format_infection(_infection_stage)
	infected_label.add_theme_color_override(&"font_color",
		COL_INFECTED if _infection_stage == &"infected" else COL_FEVER)


static func format_infection(stage: StringName) -> String:
	match stage:
		&"feverish": return "Feverish"
		&"infected": return "Infected"
	return ""


func _on_infection_stage_changed(c: Node, stage: StringName) -> void:
	if _is_player(c):
		_infection_stage = stage
		_refresh_body()


func _on_bandage_interrupted(c: Node, _region: StringName) -> void:
	if _is_player(c):
		_notice("Interrupted", 1.5)


## Pure: one line per wound, bleeding first ("✚ Left leg — Laceration  BLEEDING").
static func format_injuries(summary: Array) -> String:
	if summary.is_empty():
		return "No injuries"
	var lines: PackedStringArray = ["Injuries:"]
	for d in summary:
		var tag := ""
		if bool(d.get("bleeding", false)):
			tag = "  BLEEDING"
		elif bool(d.get("bandaged", false)):
			tag = "  (bandaged)"
		lines.append("• %s%s" % [String(d.get("label", "?")), tag])
	return "\n".join(lines)


static func format_pain(value: float, max_value: float) -> String:
	var pct := 0 if max_value <= 0.0 else int(round(value / max_value * 100.0))
	return "Pain %d%%" % pct


static func format_weapon(item: Dictionary) -> String:
	var mx := int(item.get("max_condition", 0))
	if mx <= 0:
		return "Weapon: %s" % String(item.get("name", "Fists"))
	return "Weapon: %s  (%d/%d)" % [String(item.get("name", "?")), int(item.get("condition", 0)), mx]


func _on_weapon_changed(actor: Node, item: Dictionary) -> void:
	if actor != null and not _is_player(actor):
		return
	weapon_label.text = format_weapon(item)
	var mx := int(item.get("max_condition", 0))
	condition_bar.visible = mx > 0
	if mx > 0:
		var f := float(item.get("condition", 0)) / float(mx)
		condition_bar.value = f * 100.0
		condition_bar.modulate = COL_OK if f > 0.5 else (COL_LOW if f > 0.2 else COL_EXHAUSTED)


func _on_weapon_broken(actor: Node, item: Dictionary) -> void:
	if _is_player(actor):
		_notice("%s broke!" % String(item.get("name", "Weapon")), 2.0)


func _on_item_picked_up(actor: Node, item: Dictionary) -> void:
	if _is_player(actor):
		_notice("Picked up %s" % String(item.get("name", "item")), 1.5)


func _on_attack_refused(actor: Node, reason: String) -> void:
	if _is_player(actor):
		_notice(reason, 1.5)


func _on_aim_changed(actor: Node, aiming: bool, in_reach: int) -> void:
	if not _is_player(actor):
		return
	aim_label.text = format_aim(aiming, in_reach)


static func format_aim(aiming: bool, in_reach: int) -> String:
	if not aiming:
		return ""
	return "Aiming — %d in reach" % in_reach


func _on_bandage_started(c: Node, region: StringName, seconds: float) -> void:
	if _is_player(c):
		_notice("Bandaging %s…" % Injury.REGION_LABELS[maxi(Injury.region_from_id(region), 0)].to_lower(), seconds)


func _on_bandage_finished(c: Node, region: StringName) -> void:
	if _is_player(c):
		_notice("Bandaged %s" % Injury.REGION_LABELS[maxi(Injury.region_from_id(region), 0)].to_lower(), 1.5)


func _on_character_damaged(c: Node, _amount: float, _source: Node, _info: Dictionary) -> void:
	if not _is_player(c):
		return
	var ch := c as Character
	if ch and ch.health:
		_health_frac = ch.health.fraction()
	_refresh()
	flash_damage()


func _on_character_died(c: Node, _source: Node) -> void:
	if not _is_player(c):
		return
	_dead = true
	_health_frac = 0.0
	death_overlay.visible = true
	prompt_label.text = ""
	_refresh()


## Red screen-edge flash (0.55 s).
func flash_damage() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_set_flash(0.9)
	_flash_tween = create_tween()
	_flash_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_flash_tween.tween_method(_set_flash, 0.9, 0.0, 0.55).set_ease(Tween.EASE_IN)


func _set_flash(v: float) -> void:
	var m := damage_flash.material as ShaderMaterial
	if m:
		m.set_shader_parameter(&"strength", v)


func flash_strength() -> float:
	var m := damage_flash.material as ShaderMaterial
	return float(m.get_shader_parameter(&"strength")) if m else 0.0


func _on_zombie_state_changed(zombie: Node, _from: StringName, to: StringName) -> void:
	var chasing: bool = (to == &"chase" or to == &"attack") and GameManager.player != null and zombie.get("target") == GameManager.player
	if chasing:
		if not _chasers.has(zombie):
			_chasers[zombie] = true
			# A chaser removed from the tree (freed, scene change) must not
			# leave a stale count behind.
			zombie.tree_exiting.connect(_on_chaser_gone.bind(zombie), CONNECT_ONE_SHOT)
	else:
		_forget_chaser(zombie)
	_refresh_danger()


func _on_zombie_died(zombie: Node, _killer: Node) -> void:
	_forget_chaser(zombie)
	_refresh_danger()


func _on_chaser_gone(zombie: Node) -> void:
	_chasers.erase(zombie)
	_refresh_danger()


func _forget_chaser(zombie: Node) -> void:
	if _chasers.erase(zombie) and is_instance_valid(zombie):
		var cb := _on_chaser_gone.bind(zombie)
		if zombie.tree_exiting.is_connected(cb):
			zombie.tree_exiting.disconnect(cb)


func chasing_count() -> int:
	_prune_chasers()
	return _chasers.size()


func _prune_chasers() -> void:
	for z in _chasers.keys():
		if not is_instance_valid(z) or not z.is_inside_tree():
			_chasers.erase(z)


func _refresh_danger() -> void:
	_prune_chasers()
	danger_label.text = format_danger(_chasers.size())


static func format_danger(n: int) -> String:
	if n <= 0:
		return ""
	return "!  %d chasing" % n


func restart_action_name() -> StringName:
	return &"restart"


func _unhandled_input(event: InputEvent) -> void:
	if _dead and event.is_action_pressed(restart_action_name()):
		get_viewport().set_input_as_handled()
		restart()


## Reload the running scene (no-op in tests where the scene is not current).
func restart() -> void:
	var t := get_tree()
	if t.current_scene != null and t.current_scene.is_ancestor_of(self):
		t.reload_current_scene()


func _notice(text: String, seconds: float) -> void:
	notice_label.text = text
	_notice_time = seconds


func _refresh() -> void:
	stamina_bar.value = _frac * 100.0
	health_bar.value = _health_frac * 100.0
	health_label.text = "♥ Health %d%%" % int(round(_health_frac * 100.0)) if not _dead else "♥ Dead"
	stamina_label.text = format_stamina(_frac, _stamina_cap, _stamina_state == &"low")
	var mode := "Idle" if _idle else String(_mode).capitalize()
	if _exhausted:
		mode += "  (EXHAUSTED)"
	mode_label.text = mode
	stamina_bar.modulate = COL_EXHAUSTED if _exhausted else (COL_LOW if _stamina_state == &"low" else COL_OK)


## "Stamina 60 %" (+ " (low)") (+ " · max 80 %" when wounds lower the cap).
static func format_stamina(frac: float, cap: float, low: bool) -> String:
	var t := "Stamina %d %%" % int(round(frac * 100.0))
	if low:
		t += " (low)"
	if cap < 0.995:
		t += " · max %d %%" % int(round(cap * 100.0))
	return t


func _process(delta: float) -> void:
	if _flash_time > 0.0:
		_flash_time = maxf(0.0, _flash_time - delta)
		if fmod(_flash_time, 0.3) < 0.15:
			stamina_bar.modulate = Color.WHITE
		else:
			_refresh()
	if _notice_time > 0.0:
		_notice_time = maxf(0.0, _notice_time - delta)
		if _notice_time == 0.0:
			notice_label.text = ""
	# Exhausted flag can clear via the winded timer without a stat event.
	var p := GameManager.player as Character
	if p and p.exhausted != _exhausted:
		_exhausted = p.exhausted
		_refresh()
	if p:
		var idle := not p.is_moving()
		if idle != _idle:
			_idle = idle
			_refresh()
		# Continuous meters (not events): charge and bandage progress.
		var combat := p.get_node_or_null("Combat")
		var cf: float = combat.charge_fraction() if combat else -1.0
		charge_bar.visible = cf >= 0.0
		if cf >= 0.0:
			charge_bar.value = cf * 100.0
		var bp: float = p.injuries.bandage_progress() if p.injuries else -1.0
		bandage_bar.visible = bp >= 0.0
		if bp >= 0.0:
			bandage_bar.value = bp * 100.0
	if not _chasers.is_empty():
		var n := _chasers.size()
		_prune_chasers()
		if _chasers.size() != n:
			danger_label.text = format_danger(_chasers.size())

	debug_label.visible = GameManager.debug_overlay
	if debug_label.visible and p:
		debug_label.text = "pos %.1f, %.1f, %.1f\nspeed %.2f m/s\nfps %d" % [
			p.global_position.x, p.global_position.y, p.global_position.z,
			p.speed(), Engine.get_frames_per_second()]
