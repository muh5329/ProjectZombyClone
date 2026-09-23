class_name Injury
extends RefCounted
## One wound on one body region. Plain data + tiny helpers; the numbers
## per type live in InjuryProfile / InjuryTypeSpec, the behaviour
## (bleeding, healing, infection, effects) in InjuryComponent.

enum Region {
	HEAD, NECK, UPPER_TORSO, LOWER_TORSO,
	LEFT_ARM, RIGHT_ARM, LEFT_HAND, RIGHT_HAND,
	LEFT_LEG, RIGHT_LEG,
}
enum Type { SCRATCH, LACERATION, DEEP_WOUND, BITE, BURN, FRACTURE }

## StringName ids used in event payloads, damage info and data weights.
const REGION_IDS: Array[StringName] = [
	&"head", &"neck", &"upper_torso", &"lower_torso",
	&"left_arm", &"right_arm", &"left_hand", &"right_hand",
	&"left_leg", &"right_leg",
]
const REGION_LABELS: Array[String] = [
	"Head", "Neck", "Upper torso", "Lower torso",
	"Left arm", "Right arm", "Left hand", "Right hand",
	"Left leg", "Right leg",
]
const TYPE_IDS: Array[StringName] = [&"scratch", &"laceration", &"deep_wound", &"bite", &"burn", &"fracture"]
const TYPE_LABELS: Array[String] = ["Scratch", "Laceration", "Deep wound", "Bite", "Burn", "Fracture"]

var region: Region = Region.UPPER_TORSO
var type: Type = Type.SCRATCH
## True while the wound bleeds (stops when bandaged or when bleed_left runs out).
var bleeding: bool = false
## Seconds of bleeding left (INF = until bandaged).
var bleed_left: float = INF
## Seconds until healed (bandaged wounds heal faster).
var heal_left: float = 60.0
var heal_total: float = 60.0
var bandaged: bool = false
## Quality of the dressing (MedicalData.bandage_quality: 1 bandage, 0.5
## rag). Only meaningful while bandaged; scales the heal speed-up.
var bandage_quality: float = 1.0
## Seconds until a makeshift dressing gives way (-1 = it holds).
var rebleed_left: float = -1.0
## Carries the zombie infection (rolled once when inflicted).
var infected: bool = false
## Seconds since inflicted.
var age: float = 0.0


func _init(p_region: Region = Region.UPPER_TORSO, p_type: Type = Type.SCRATCH) -> void:
	region = p_region
	type = p_type


func region_id() -> StringName:
	return REGION_IDS[region]


func type_id() -> StringName:
	return TYPE_IDS[type]


func is_leg() -> bool:
	return is_leg_region(region)


func label() -> String:
	return "%s — %s" % [REGION_LABELS[region], TYPE_LABELS[type]]


func to_dict() -> Dictionary:
	return {
		"region": region_id(), "type": type_id(), "label": label(),
		"region_label": REGION_LABELS[region], "type_label": TYPE_LABELS[type],
		"bleeding": bleeding, "bandaged": bandaged, "infected": infected,
		"bandage_quality": bandage_quality,
		"heal_fraction": 1.0 - (heal_left / heal_total if heal_total > 0.0 else 0.0),
	}


## Full state for the save (to_dict() is the UI summary). INF timers are
## stored as -1 (JSON has no infinity).
func save_dict() -> Dictionary:
	return {
		"region": String(region_id()), "type": String(type_id()),
		"bleeding": bleeding, "bleed_left": bleed_left if is_finite(bleed_left) else -1.0,
		"heal_left": heal_left, "heal_total": heal_total, "bandaged": bandaged,
		"bandage_quality": bandage_quality, "rebleed_left": rebleed_left,
		"infected": infected, "age": age,
	}


## Rebuild from save_dict(); null for an unknown region / type.
static func from_save(d: Dictionary) -> Injury:
	var r := region_from_id(StringName(String(d.get("region", ""))))
	var t := type_from_id(StringName(String(d.get("type", ""))))
	if r < 0 or t < 0:
		return null
	var inj := Injury.new(r, t)
	inj.bleeding = bool(d.get("bleeding", false))
	var bl := float(d.get("bleed_left", -1.0))
	inj.bleed_left = bl if bl >= 0.0 else INF
	inj.heal_total = maxf(float(d.get("heal_total", 60.0)), 0.1)
	inj.heal_left = clampf(float(d.get("heal_left", inj.heal_total)), 0.0, inj.heal_total)
	inj.bandaged = bool(d.get("bandaged", false))
	inj.bandage_quality = float(d.get("bandage_quality", 1.0))
	inj.rebleed_left = float(d.get("rebleed_left", -1.0))
	inj.infected = bool(d.get("infected", false))
	inj.age = maxf(float(d.get("age", 0.0)), 0.0)
	return inj


static func is_leg_region(r: int) -> bool:
	return r == Region.LEFT_LEG or r == Region.RIGHT_LEG


## Region enum for an id (&"left_leg"), or -1.
static func region_from_id(id: StringName) -> int:
	return REGION_IDS.find(id)


static func type_from_id(id: StringName) -> int:
	return TYPE_IDS.find(id)


## Pure weighted pick: [weights] maps ids to weights (need not sum to 1),
## [r] is a uniform number in [0, 1). Returns &"" for empty weights.
static func roll_weighted(weights: Dictionary, r: float) -> StringName:
	var total := 0.0
	for k in weights:
		total += maxf(float(weights[k]), 0.0)
	if total <= 0.0:
		return &""
	var x := clampf(r, 0.0, 0.999999) * total
	var last: StringName = &""
	for k in weights:
		var w := maxf(float(weights[k]), 0.0)
		if w <= 0.0:
			continue
		last = StringName(k)
		if x < w:
			return last
		x -= w
	return last
