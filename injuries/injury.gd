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
		"heal_fraction": 1.0 - (heal_left / heal_total if heal_total > 0.0 else 0.0),
	}


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
