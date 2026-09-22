class_name InjuryComponent
extends Node
## Body-region injuries for a Character (child node "Injuries").
##
## - Any hit whose info carries a `type` (&"scratch", &"bite"…) becomes an
##   Injury on info.region (&"random" / missing → rolled from the
##   profile's default_region_weights). info.infectious (zombies) rolls
##   the type's infection chance.
## - Climbing through a smashed window (EventBus.window_climbed, hazard)
##   lacerates a hand / arm / leg.
## - Effects (recomputed on every change): bleeding drains health through
##   HealthComponent.drain(); leg wounds set the MovementComponent
##   modifier &"injury"; open wounds lower max stamina; the `pain` stat is
##   the capped sum of wound pain; an infected wound makes the
##   `infection` stat rise slowly (lethal only after long game time).
## - bandage_worst(): B key — bandages the worst bleeding wound in
##   profile.bandage_seconds of busy time (the Character owns the tween).
##   Round 5: needs a dressing (MedicalData.bandage_quality > 0: bandage,
##   rag) in the character's `inventory` (ItemContainer) — refused "No
##   bandages" otherwise. The best one is taken when bandaging starts
##   (consumed) and given back if the bandaging is interrupted. The
##   quality is recorded on the wound (a rag heals slower) and a makeshift
##   dressing may give way: MedicalData.rebleed_chance (rag 50 %) that the
##   wound bleeds again after rebleed_after (60 s) → wound_reopened.
## The pure effect maths are static (unit-tested without a scene).
## Everything is announced through EventBus.injuries_changed.

const PAIN := &"pain"
const INFECTION := &"infection"
const BANDAGE_CONTEXT := &"bandage"

@export var profile: InjuryProfile

var injuries: Array[Injury] = []
## True once any wound carried the infection (it never goes away).
var infected: bool = false
var rng := RandomNumberGenerator.new()
var character: Character
## The wound being bandaged (null when not bandaging).
var bandaging: Injury = null
## The dressing being applied (taken out of the inventory; returned on
## interrupt).
var _dressing: ItemInstance = null
## Container the dressing was taken from (weak): refunds go back there.
var _dressing_from: WeakRef = null
## Visible infection stage (&"none" until symptoms, see profile thresholds).
var infection_stage: StringName = &"none"
var _bandage_left: float = 0.0

var _accum: float = 0.0
var _drip_accum: float = 0.0


func _ready() -> void:
	if profile == null:
		profile = load("res://data/injuries/human_injuries.tres")
	rng.randomize()


## Called by Character._ready (after its stats exist).
func setup(c: Character) -> void:
	character = c
	c.stats.add_stat(PAIN, profile.pain_max)
	c.stats.set_value(PAIN, 0.0)
	c.stats.add_stat(INFECTION, 100.0)
	c.stats.set_value(INFECTION, 0.0)
	c.stats.changed.connect(_on_stat_changed)
	if c.health:
		c.health.damaged.connect(_on_damaged)
	EventBus.window_climbed.connect(_on_window_climbed)


# --- Inflicting --------------------------------------------------------------

func _on_damaged(_amount: float, _source: Node, info: Dictionary) -> void:
	if is_bandaging():
		interrupt_bandage()
	var type := Injury.type_from_id(StringName(info.get("type", &"")))
	if type < 0:
		return
	var region := Injury.region_from_id(StringName(info.get("region", &"random")))
	if region < 0:
		region = roll_region(profile.default_region_weights)
	add_injury(region, type, bool(info.get("infectious", false)))


func _on_window_climbed(actor: Node, window: Node, hazard: bool) -> void:
	if actor != character or not hazard or character.is_dead():
		return
	if rng.randf() >= profile.glass_laceration_chance:
		return
	var region := roll_region(profile.glass_region_weights)
	character.take_damage(profile.glass_damage, window, {"region": Injury.REGION_IDS[region], "type": &"laceration"})


func roll_region(weights: Dictionary) -> int:
	var id := Injury.roll_weighted(weights, rng.randf())
	var r := Injury.region_from_id(id)
	return r if r >= 0 else Injury.Region.UPPER_TORSO


## Add a wound. [infectious]: inflicted by a zombie (rolls the type's
## infection chance).
func add_injury(region: int, type: int, infectious: bool = false) -> Injury:
	var spec := profile.spec(type)
	var inj := Injury.new(region, type)
	inj.bleeding = spec.bleed_rate > 0.0
	inj.bleed_left = spec.bleed_seconds if spec.bleed_seconds > 0.0 else INF
	inj.heal_total = maxf(spec.heal_seconds, 0.1)
	inj.heal_left = inj.heal_total
	if infectious and rng.randf() < spec.infection_chance:
		inj.infected = true
		infected = true
	injuries.append(inj)
	_changed()
	return inj


# --- Queries -----------------------------------------------------------------

func bleeding_count() -> int:
	var n := 0
	for i in injuries:
		if i.bleeding:
			n += 1
	return n


func injuries_on(region: int) -> Array[Injury]:
	var out: Array[Injury] = []
	for i in injuries:
		if i.region == region:
			out.append(i)
	return out


## The wound to bandage next: the bleeding, unbandaged wound with the
## highest profile.bandage_priority (ties → faster bleeder); null when
## nothing qualifies (fractures / burns never do).
func worst_unbandaged() -> Injury:
	var best: Injury = null
	var best_score := -INF
	for i in injuries:
		if i.bandaged or not i.bleeding:
			continue
		var prio: Variant = profile.bandage_priority.get(i.type_id())
		if prio == null:
			continue
		var score := float(prio) * 1000.0 + profile.spec(i.type).bleed_rate
		if score > best_score:
			best_score = score
			best = i
	return best


func bleed_rate() -> float:
	return total_bleed_rate(injuries, profile)


func pain() -> float:
	return character.stats.get_value(PAIN) if character else 0.0


func infection() -> float:
	return character.stats.get_value(INFECTION) if character else 0.0


func summary() -> Array:
	var sorted := injuries.duplicate()
	sorted.sort_custom(func(a: Injury, b: Injury) -> bool:
		if a.bleeding != b.bleeding:
			return a.bleeding
		return profile.spec(a.type).pain > profile.spec(b.type).pain)
	var out: Array = []
	for i: Injury in sorted:
		out.append(i.to_dict())
	return out


# --- Pure effect maths (unit-tested) ------------------------------------------

static func total_bleed_rate(list: Array[Injury], p: InjuryProfile) -> float:
	var r := 0.0
	for i in list:
		if i.bleeding:
			r += p.spec(i.type).bleed_rate * (p.bandaged_bleed_multiplier if i.bandaged else 1.0)
	return r


static func total_pain(list: Array[Injury], p: InjuryProfile) -> float:
	var t := 0.0
	for i in list:
		t += p.spec(i.type).pain * (p.bandaged_pain_multiplier if i.bandaged else 1.0)
	return minf(t, p.pain_max)


## Product of the leg wounds' slow factors (bandaged wounds slow half as
## much), never below profile.min_leg_speed_multiplier.
static func leg_speed_multiplier(list: Array[Injury], p: InjuryProfile) -> float:
	var m := 1.0
	for i in list:
		if not i.is_leg():
			continue
		var f := p.spec(i.type).leg_speed_multiplier
		if i.bandaged:
			f = 1.0 - (1.0 - f) * p.bandaged_slow_factor
		m *= f
	return maxf(m, p.min_leg_speed_multiplier)


## (damage multiplier, swing time multiplier) for a pain value.
static func pain_combat_modifiers(pain_value: float, p: InjuryProfile) -> Vector2:
	if pain_value > p.pain_severe_threshold:
		return Vector2(p.pain_severe_damage_multiplier, p.pain_severe_swing_time_multiplier)
	if pain_value > p.pain_moderate_threshold:
		return Vector2(p.pain_moderate_damage_multiplier, p.pain_moderate_swing_time_multiplier)
	return Vector2.ONE


## &"none" / &"feverish" / &"infected" for an infection value (0..100).
static func infection_stage_for(value: float, p: InjuryProfile) -> StringName:
	if value >= p.infected_threshold:
		return &"infected"
	if value >= p.fever_threshold:
		return &"feverish"
	return &"none"


static func max_stamina_penalty(list: Array[Injury], p: InjuryProfile) -> float:
	var t := 0.0
	for i in list:
		t += p.spec(i.type).max_stamina_penalty
	return minf(t, p.max_stamina_penalty_cap)


## Healing speed of a wound: 1 unbandaged; bandaged wounds heal
## profile.bandaged_heal_multiplier × faster with a clean bandage, less
## with a rag (the speed-up scales with the dressing quality).
static func heal_rate(inj: Injury, p: InjuryProfile) -> float:
	if not inj.bandaged:
		return 1.0
	return 1.0 + (p.bandaged_heal_multiplier - 1.0) * clampf(inj.bandage_quality, 0.0, 1.0)


# --- Treatment -----------------------------------------------------------------

## Start bandaging the worst wound: [profile.bandage_seconds] of busy time
## owned by the character. Returns {ok, reason?, region?}. [preferred]:
## use that dressing (inventory "Use" on a rag); default the best one in
## any carried container (main inventory, worn bag).
func bandage_worst(preferred: ItemInstance = null) -> Dictionary:
	if character == null or character.is_dead():
		return _refuse("Can't bandage now")
	if character.is_busy:
		return _refuse("Busy")
	var inj := worst_unbandaged()
	if inj == null:
		return _refuse("Nothing to bandage")
	var dressing: ItemInstance = null
	if preferred != null and preferred.data is MedicalData and (preferred.data as MedicalData).bandage_quality > 0.0 \
			and _storage().has(preferred.owner_container()):
		dressing = preferred
	else:
		var q := 0.0
		for c in _storage():
			var d := best_dressing_in(c)
			if d != null and (d.data as MedicalData).bandage_quality > q:
				q = (d.data as MedicalData).bandage_quality
				dressing = d
	if dressing == null:
		return _refuse("No bandages")
	_dressing_from = weakref(dressing.owner_container())
	_dressing = dressing.owner_container().remove(dressing, 1)
	bandaging = inj
	_bandage_left = profile.bandage_seconds
	var tw := character.begin_busy(BANDAGE_CONTEXT)
	tw.tween_interval(profile.bandage_seconds)
	tw.tween_callback(_finish_bandage.bind(inj))
	EventBus.bandage_started.emit(character, inj.region_id(), profile.bandage_seconds)
	return {"ok": true, "region": inj.region_id(), "dressing": _dressing.id()}


## The character's carried ItemContainer (duck-typed `inventory`), or null.
func _inventory() -> ItemContainer:
	if character == null:
		return null
	var inv: Variant = character.get("inventory")
	return inv as ItemContainer if inv is ItemContainer else null


## Carried containers to look for dressings in (duck-typed
## character.carried_storage(); else its `inventory`).
func _storage() -> Array:
	if character != null and character.has_method(&"carried_storage"):
		return character.call(&"carried_storage")
	var inv := _inventory()
	return [inv] if inv != null else []


## Pure: the best dressing in [inv] (highest bandage_quality), or null.
static func best_dressing_in(inv: ItemContainer) -> ItemInstance:
	if inv == null:
		return null
	var best: ItemInstance = null
	var q := 0.0
	for it in inv.items:
		var m := it.data as MedicalData
		if m and m.bandage_quality > q:
			q = m.bandage_quality
			best = it
	return best


func is_bandaging() -> bool:
	return bandaging != null and character != null and character.is_busy and character.busy_context == BANDAGE_CONTEXT


## 0..1 while bandaging (HUD progress bar), -1 otherwise.
func bandage_progress() -> float:
	if not is_bandaging():
		return -1.0
	return clampf(1.0 - _bandage_left / maxf(profile.bandage_seconds, 0.01), 0.0, 1.0)


## Getting hurt stops the bandaging (the wound stays unbandaged).
func interrupt_bandage() -> void:
	if not is_bandaging():
		return
	var region := bandaging.region_id()
	bandaging = null
	# The dressing was not used: give it back.
	_refund_dressing()
	if character.busy_tween and character.busy_tween.is_valid():
		character.busy_tween.kill()
	character.end_busy()
	EventBus.bandage_interrupted.emit(character, region)


func _finish_bandage(inj: Injury) -> void:
	bandaging = null
	if not injuries.has(inj):
		# The wound healed / vanished meanwhile: the dressing was not used.
		_refund_dressing()
		return
	var med := _dressing.data as MedicalData if _dressing != null else null
	_dressing = null
	inj.bandaged = true
	inj.bandage_quality = med.bandage_quality if med else 1.0
	inj.rebleed_left = -1.0
	if med and med.rebleed_chance > 0.0 and rng.randf() < med.rebleed_chance:
		inj.rebleed_left = med.rebleed_after
	if profile.bandaged_bleed_multiplier <= 0.0:
		inj.bleeding = false
	EventBus.bandage_finished.emit(character, inj.region_id())
	_changed()


## Put the taken dressing back in the inventory; when it no longer fits
## (or there is none) drop it as a WorldItem at the character's feet.
func _refund_dressing() -> void:
	var d := _dressing
	_dressing = null
	if d == null or d.stack <= 0:
		return
	# Back where it came from (worn bag or main inventory), else the main
	# inventory, else the floor.
	var origin: ItemContainer = _dressing_from.get_ref() as ItemContainer if _dressing_from != null else null
	_dressing_from = null
	if origin != null and _storage().has(origin) and origin.add(d).get("ok", false):
		return
	var inv := _inventory()
	if inv != null and inv != origin and inv.add(d).get("ok", false):
		return
	if character == null or character.get_parent() == null:
		return
	var w := WorldItem.for_instance(d)
	character.get_parent().add_child(w)
	w.global_position = character.global_position * Vector3(1, 0, 1) + Vector3(0, character.global_position.y - 0.1, 0) + character.facing_vector() * 0.4


func _refuse(reason: String) -> Dictionary:
	EventBus.interaction_refused.emit(character, null, reason)
	return {"ok": false, "reason": reason}


# --- Tick ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if character == null:
		return
	if bandaging != null:
		_bandage_left = maxf(_bandage_left - delta, 0.0)
	_accum += delta
	if _accum < 1.0 / maxf(profile.tick_hz, 0.1):
		return
	var dt := _accum
	_accum = 0.0
	tick(dt)


## Advance bleeding / healing / infection by [dt] seconds (tests call it
## directly to fast-forward).
func tick(dt: float) -> void:
	if character == null or character.is_dead():
		return
	var dirty := false
	var bleed := bleed_rate()
	if bleed > 0.0 and character.health:
		character.health.drain(bleed * dt, null, &"bleeding")
		_drip_accum += dt
		if _drip_accum >= profile.blood_drip_interval:
			_drip_accum = 0.0
			EventBus.blood_spilled.emit(character.global_position, clampf(bleed * 2.0, 0.2, 1.0))
	for i in range(injuries.size() - 1, -1, -1):
		var inj := injuries[i]
		inj.age += dt
		if inj.bandaged and inj.rebleed_left > 0.0:
			inj.rebleed_left -= dt
			if inj.rebleed_left <= 0.0:
				_reopen(inj)
				dirty = true
		if inj.bleeding and not inj.bandaged:
			inj.bleed_left -= dt
			if inj.bleed_left <= 0.0:
				inj.bleeding = false
				dirty = true
		inj.heal_left -= dt * heal_rate(inj, profile)
		if inj.heal_left <= 0.0 and inj != bandaging:
			injuries.remove_at(i)
			dirty = true
	if infected:
		character.stats.modify(INFECTION, profile.infection_rise_per_second * dt)
		if character.stats.get_fraction(INFECTION) >= 1.0 and character.health:
			character.health.drain(profile.infection_lethal_damage_per_second * dt, null, &"infection")
	if dirty:
		_changed()


## A makeshift dressing gave way: the wound is unbandaged and bleeds again
## (for its type's full bleed time).
func _reopen(inj: Injury) -> void:
	inj.rebleed_left = -1.0
	inj.bandaged = false
	var spec := profile.spec(inj.type)
	if spec.bleed_rate > 0.0:
		inj.bleeding = true
		inj.bleed_left = spec.bleed_seconds if spec.bleed_seconds > 0.0 else INF
	EventBus.wound_reopened.emit(character, inj.region_id())


func _on_stat_changed(stat: StringName, value: float, _max_value: float) -> void:
	if stat != INFECTION:
		return
	var stage := infection_stage_for(value, profile)
	if stage != infection_stage:
		infection_stage = stage
		EventBus.infection_stage_changed.emit(character, stage)


func _changed() -> void:
	_apply_effects()
	EventBus.injuries_changed.emit(character, summary())


func _apply_effects() -> void:
	if character == null:
		return
	character.stats.set_value(PAIN, total_pain(injuries, profile))
	character.movement.set_modifier(&"injury", leg_speed_multiplier(injuries, profile))
	var base := character.profile.stamina_max if character.profile else 100.0
	character.stats.set_max(Character.STAMINA, base - max_stamina_penalty(injuries, profile))
