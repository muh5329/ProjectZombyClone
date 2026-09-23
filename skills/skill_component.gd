class_name SkillComponent
extends Node
## Perk / skill levels of a character (child "Skills" of the Player).
## Round 9 ships one real skill, Carpentry: +XP per nailed plank /
## disassembled piece; levels 0-10 shorten carpentry actions (−5 % per
## level) and strengthen new planks (+5 % per level). Other skills from the
## brief (Fitness, Cooking, First Aid…) plug in by id with the same XP
## table.
##
## Pure statics (unit-tested): level_for_xp(), xp_for_level(),
## carpentry_time_multiplier(), carpentry_health_multiplier().
## EventBus: skill_xp_gained(character, skill, xp), skill_leveled(character,
## skill, level). to_dict / from_dict for the save (Round 10).

signal leveled(skill: StringName, level: int)

const CARPENTRY := &"carpentry"
const MAX_LEVEL := 10
## Cumulative XP needed for levels 1..10.
const XP_TABLE: Array[float] = [30.0, 80.0, 150.0, 240.0, 350.0, 480.0, 630.0, 800.0, 1000.0, 1250.0]
## Per-level effect of Carpentry.
const CARPENTRY_TIME_PER_LEVEL := 0.05
const CARPENTRY_HEALTH_PER_LEVEL := 0.05

## skill id → accumulated XP.
var xp: Dictionary = {}
var character: Node = null


func _ready() -> void:
	if character == null:
		character = get_parent()


static func level_for_xp(amount: float) -> int:
	var lvl := 0
	for t in XP_TABLE:
		if amount >= t:
			lvl += 1
		else:
			break
	return mini(lvl, MAX_LEVEL)


## Cumulative XP needed for [level] (0 for level 0).
static func xp_for_level(level: int) -> float:
	if level <= 0:
		return 0.0
	return XP_TABLE[mini(level, MAX_LEVEL) - 1]


## 1.0 at level 0, 0.5 at level 10.
static func carpentry_time_multiplier(level: int) -> float:
	return 1.0 - CARPENTRY_TIME_PER_LEVEL * clampi(level, 0, MAX_LEVEL)


## 1.0 at level 0, 1.5 at level 10.
static func carpentry_health_multiplier(level: int) -> float:
	return 1.0 + CARPENTRY_HEALTH_PER_LEVEL * clampi(level, 0, MAX_LEVEL)


func get_xp(skill: StringName) -> float:
	return float(xp.get(skill, 0.0))


func level(skill: StringName) -> int:
	return level_for_xp(get_xp(skill))


## Add [amount] XP. Returns {level, leveled_up}.
func add_xp(skill: StringName, amount: float) -> Dictionary:
	if amount <= 0.0:
		return {"level": level(skill), "leveled_up": false}
	var before := level(skill)
	xp[skill] = get_xp(skill) + amount
	var after := level(skill)
	EventBus.skill_xp_gained.emit(character, skill, amount)
	if after > before:
		leveled.emit(skill, after)
		EventBus.skill_leveled.emit(character, skill, after)
	return {"level": after, "leveled_up": after > before}


## Set a level directly (debug starts / tests): XP jumps to its threshold.
func set_level(skill: StringName, lvl: int) -> void:
	xp[skill] = xp_for_level(clampi(lvl, 0, MAX_LEVEL))


## Multipliers for carpentry actions of this character.
func carpentry_time() -> float:
	return carpentry_time_multiplier(level(CARPENTRY))


func carpentry_health() -> float:
	return carpentry_health_multiplier(level(CARPENTRY))


## Duck-typed lookup: the "Skills" child of [actor] (or null).
static func of(actor: Node) -> SkillComponent:
	return actor.get_node_or_null("Skills") as SkillComponent if actor != null else null


func to_dict() -> Dictionary:
	var out := {}
	for k in xp:
		out[String(k)] = float(xp[k])
	return {"xp": out}


func from_dict(d: Dictionary) -> void:
	xp.clear()
	var src: Dictionary = d.get("xp", {})
	for k in src:
		var v := float(src[k])
		if v > 0.0 and is_finite(v):
			xp[StringName(k)] = v
