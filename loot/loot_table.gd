class_name LootTable
extends Resource
## Data-driven loot table (a .tres under data/loot/; its id is the path
## relative to data/loot without the extension: "kitchen_cabinet",
## "garage/tool_crate"). LootResolver.roll() turns it into items.
##
## entries: [{
##     item_id:   StringName   (must exist in ItemDB — unit-tested)
##     weight:    float        relative pick weight per roll
##     min_count, max_count: int   items per successful pick (default 1)
##     chance:    float        0..1 gate after the pick (default 1)
##     rarity:    StringName   common | uncommon | rare | very_rare
##                             (default common; multiplies the chance)
## }]
## A container gets randi_range(rolls_min, rolls_max) rolls. Each roll
## picks one entry by weight, then keeps it with
##   chance × rarity multiplier × world-age multiplier
## (see LootResolver). [empty_chance] is tested first.

const RARITY_MULTIPLIERS := {
	&"common": 1.0, &"uncommon": 0.6, &"rare": 0.3, &"very_rare": 0.1,
}

@export var rolls_min: int = 1
@export var rolls_max: int = 3
@export var entries: Array[Dictionary] = []
## Chance the container is simply empty (checked first).
@export_range(0.0, 1.0) var empty_chance: float = 0.0
## Condition of generated items with a condition, as a fraction of max.
@export_range(0.0, 1.0) var condition_min: float = 0.3
@export_range(0.0, 1.0) var condition_max: float = 1.0


func item_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for e in entries:
		var iid := StringName(e.get("item_id", &""))
		if not out.has(iid):
			out.append(iid)
	return out


static func rarity_multiplier(rarity: StringName) -> float:
	return float(RARITY_MULTIPLIERS.get(StringName(rarity), 1.0))


## Problems with this table (unknown ids, bad numbers). Empty = fine.
## [label] prefixes the messages (the table id).
func validate(label: String = "") -> Array[String]:
	var problems: Array[String] = []
	var tag := label if label != "" else resource_path
	if rolls_min < 0 or rolls_max < rolls_min:
		problems.append("%s: bad rolls %d..%d" % [tag, rolls_min, rolls_max])
	if entries.is_empty():
		problems.append("%s: no entries" % tag)
	for e in entries:
		var iid := StringName(e.get("item_id", &""))
		if not ItemDB.has_item(iid):
			problems.append("%s: unknown item id '%s'" % [tag, iid])
		if float(e.get("weight", 0.0)) <= 0.0:
			problems.append("%s: '%s' has weight <= 0" % [tag, iid])
		var mn := int(e.get("min_count", 1))
		var mx := int(e.get("max_count", mn))
		if mn < 1 or mx < mn:
			problems.append("%s: '%s' bad count %d..%d" % [tag, iid, mn, mx])
		var ch := float(e.get("chance", 1.0))
		if ch <= 0.0 or ch > 1.0:
			problems.append("%s: '%s' chance %.2f outside (0, 1]" % [tag, iid, ch])
		if e.has("rarity") and not RARITY_MULTIPLIERS.has(StringName(e.rarity)):
			problems.append("%s: '%s' unknown rarity '%s'" % [tag, iid, e.rarity])
	return problems
