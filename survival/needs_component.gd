class_name NeedsComponent
extends Node
## Survival needs of a Character (child node "Needs", Round 7): hunger,
## thirst, fatigue and food sickness, each 0 (fine) … 100 (critical),
## registered as StatsComponent stats (so they save with the stats and
## announce stat_changed) — the levels are owned here.
##
## - Time: listens to EventBus.time_advanced (world time, TimeManager) and
##   simulates in whole game-minute steps, so 2×/4× and sleep speed it up
##   and advance(360) in a test is six hours. Rates per game hour come from
##   NeedsProfile by activity (exerting ×1.5, sleeping, resting).
## - Levels: NeedsMath.level_for (hysteresis) → need_level_changed /
##   moodles_changed on the EventBus when a level changes.
## - Effects (NeedsMath.effects_for), applied when levels change: max
##   stamina multiplier (Character &"needs"), stamina regeneration
##   multiplier, movement speed modifier &"needs", swing time multiplier,
##   InjuryComponent.heal_multiplier. Per step: health drain (starving /
##   dying of thirst / food poisoning) and health regeneration (only fed,
##   watered, healthy and without wounds).
## - consume(effect) applies an eaten / drunk portion (ConsumeAction).
## - [sleeping] / [resting] are set by RestComponent.

const HUNGER := NeedsMath.HUNGER
const THIRST := NeedsMath.THIRST
const FATIGUE := NeedsMath.FATIGUE
const SICKNESS := NeedsMath.SICKNESS
## Busy contexts that count as exertion (like jogging).
const EXERTING_CONTEXTS: Array[StringName] = [&"jog", &"sprint", &"climb"]

@export var profile: NeedsProfile

var character: Character
## need → level (0 = fine).
var levels: Dictionary = {HUNGER: 0, THIRST: 0, FATIGUE: 0, SICKNESS: 0}
var effects: Dictionary = {}
var sleeping: bool = false
var resting: bool = false
## Game minutes not simulated yet (< 1).
var _pending: float = 0.0
## Last moodle list sent (only changes are emitted).
var _last_moodles: Array = []


func _ready() -> void:
	if profile == null:
		profile = load("res://data/survival/needs_profile.tres")


## Called by Character._ready (after its stats exist).
func setup(c: Character) -> void:
	character = c
	c.stats.add_stat(HUNGER, 100.0)
	c.stats.set_value(HUNGER, profile.start_hunger)
	c.stats.add_stat(THIRST, 100.0)
	c.stats.set_value(THIRST, profile.start_thirst)
	c.stats.add_stat(FATIGUE, 100.0)
	c.stats.set_value(FATIGUE, profile.start_fatigue)
	c.stats.add_stat(SICKNESS, 100.0)
	c.stats.set_value(SICKNESS, 0.0)
	if not EventBus.time_advanced.is_connected(_on_time_advanced):
		EventBus.time_advanced.connect(_on_time_advanced)
	_update_levels(true)


func _exit_tree() -> void:
	if EventBus.time_advanced.is_connected(_on_time_advanced):
		EventBus.time_advanced.disconnect(_on_time_advanced)


func _enter_tree() -> void:
	if character != null and not EventBus.time_advanced.is_connected(_on_time_advanced):
		EventBus.time_advanced.connect(_on_time_advanced)


# --- Queries -----------------------------------------------------------------

func value(need: StringName) -> float:
	return character.stats.get_value(need) if character else 0.0


func level(need: StringName) -> int:
	return int(levels.get(need, 0))


func label(need: StringName) -> String:
	return NeedsMath.label_of(need, level(need), profile)


func can_sleep() -> bool:
	return NeedsMath.can_sleep(level(FATIGUE), profile)


## [{id, label, level, max_level}] for every need above "fine", worst
## (highest level fraction) first — the HUD moodle column.
func moodles() -> Array:
	var out: Array = []
	for need in NeedsMath.NEEDS:
		var lv := level(need)
		if lv <= 0:
			continue
		out.append({"id": need, "label": label(need), "level": lv,
			"max_level": NeedsMath.thresholds_of(need, profile).size()})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.level) / float(a.max_level) > float(b.level) / float(b.max_level))
	return out


# --- Simulation ------------------------------------------------------------------

func _on_time_advanced(from_minute: float, to_minute: float) -> void:
	advance_minutes(to_minute - from_minute)


## Simulate [minutes] of game time in whole-minute steps (the remainder
## waits for the next call).
func advance_minutes(minutes: float) -> void:
	if character == null or minutes <= 0.0 or character.is_dead():
		return
	_pending += minutes
	var steps := int(floor(_pending))
	if steps <= 0:
		return
	_pending -= steps
	for i in steps:
		_step(1.0)
		if character.is_dead():
			_pending = 0.0
			return


func _exerting() -> bool:
	if character.is_busy:
		return EXERTING_CONTEXTS.has(character.busy_context)
	if not character.is_moving() or not character.has_move_intent():
		return false
	return EXERTING_CONTEXTS.has(MovementComponent.mode_name(character.effective_mode))


func _step(minutes: float) -> void:
	var hours := minutes / 60.0
	var ex := _exerting()
	for need in NeedsMath.NEEDS:
		var r := NeedsMath.rate_per_hour(need, profile, ex, sleeping, resting)
		if r != 0.0:
			character.stats.modify(need, r * hours)
	_update_levels()
	var drain := float(effects.get("health_drain", 0.0))
	if drain > 0.0 and character.health:
		character.health.drain(drain * hours, null, &"needs")
	elif bool(effects.get("regen", false)) and character.health and not character.health.dead \
			and character.health.health < character.health.max_health \
			and (character.injuries == null or character.injuries.injuries.is_empty()):
		character.health.heal(profile.health_regen_per_hour * hours)


## Recompute levels; emit and re-apply effects when any changed.
func _update_levels(force: bool = false) -> void:
	var changed := force
	for need in NeedsMath.NEEDS:
		var old := level(need)
		var lv := NeedsMath.level_for(value(need), old, NeedsMath.thresholds_of(need, profile), profile.hysteresis)
		if lv != old:
			levels[need] = lv
			changed = true
			EventBus.need_level_changed.emit(character, need, lv, label(need))
	if changed:
		_apply_effects()


func _apply_effects() -> void:
	effects = NeedsMath.effects_for(levels, profile)
	character.set_stamina_max_multiplier(&"needs", float(effects.max_stamina))
	character.stats.set_regen_multiplier(Character.STAMINA, &"needs", float(effects.stamina_regen))
	var spd := float(effects.speed)
	if is_equal_approx(spd, 1.0):
		character.movement.clear_modifier(&"needs")
	else:
		character.movement.set_modifier(&"needs", spd)
	character.set_swing_time_multiplier(&"needs", float(effects.swing_time))
	if character.injuries:
		character.injuries.heal_multiplier = float(effects.heal)
	var m := moodles()
	if m != _last_moodles:
		_last_moodles = m
		EventBus.moodles_changed.emit(character, m)


# --- Consumption --------------------------------------------------------------------

## Apply an eaten / drunk portion: {hunger, thirst} are reductions,
## sickness is added (NeedsMath.consume_effect).
func consume(effect: Dictionary) -> void:
	if character == null:
		return
	character.stats.modify(HUNGER, -float(effect.get("hunger", 0.0)))
	character.stats.modify(THIRST, -float(effect.get("thirst", 0.0)))
	character.stats.modify(SICKNESS, float(effect.get("sickness", 0.0)))
	_update_levels()


## Set a need directly (debug, tests, save).
func set_need(need: StringName, v: float) -> void:
	if character == null:
		return
	character.stats.set_value(need, v)
	_update_levels()


# --- Save ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var d := {}
	for need in NeedsMath.NEEDS:
		d[String(need)] = value(need)
	return d


func from_dict(d: Dictionary) -> void:
	for need in NeedsMath.NEEDS:
		if d.has(String(need)):
			character.stats.set_value(need, float(d[String(need)]))
	# Loading is not a transition: settle levels from scratch.
	for need in NeedsMath.NEEDS:
		levels[need] = NeedsMath.level_for(value(need), 0, NeedsMath.thresholds_of(need, profile), profile.hysteresis)
	_apply_effects()
