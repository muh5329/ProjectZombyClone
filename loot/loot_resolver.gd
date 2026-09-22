class_name LootResolver
extends RefCounted
## Pure loot maths: static functions only, randomness from the caller's
## RandomNumberGenerator (same table + same seed + same world age → same
## items; containers roll lazily on first open and never re-roll).
##
## roll(table, rng, world_age_days) -> [{id: StringName, count: int,
## condition: int (-1 = none)}]:
##   1. rng < empty_chance → nothing.
##   2. rolls = randi_range(rolls_min, rolls_max).
##   3. per roll: pick an entry by weight; keep it when
##      rng < chance × rarity multiplier × age_multiplier(world_age);
##      count = randi_range(min_count, max_count). Items with a condition
##      become one entry each with a random condition in
##      [condition_min, condition_max] × max_condition.
## Per roll the main rng draws only the pick and a sub-rng seed; the gate,
## count and conditions come from the sub-rng, so thinning (world age)
## only removes items and never reshuffles the rest.
##
## World age ("loot thins over time"): chance × max(0.2, 1 − age / 60).

const AGE_FULL_DAYS := 60.0
const AGE_FLOOR := 0.2


static func age_multiplier(world_age_days: float) -> float:
	return maxf(AGE_FLOOR, 1.0 - maxf(world_age_days, 0.0) / AGE_FULL_DAYS)


## Probability that a picked [entry] is kept.
static func effective_chance(entry: Dictionary, world_age_days: float = 0.0) -> float:
	var ch := clampf(float(entry.get("chance", 1.0)), 0.0, 1.0)
	ch *= LootTable.rarity_multiplier(StringName(entry.get("rarity", &"common")))
	return ch * age_multiplier(world_age_days)


static func roll(table: LootTable, rng: RandomNumberGenerator, world_age_days: float = 0.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if table == null or table.entries.is_empty():
		return out
	if rng.randf() < table.empty_chance:
		return out
	var rolls := rng.randi_range(table.rolls_min, maxi(table.rolls_max, table.rolls_min))
	var weights := PackedFloat64Array()
	var total := 0.0
	for e in table.entries:
		var w := maxf(float(e.get("weight", 0.0)), 0.0)
		weights.append(w)
		total += w
	if total <= 0.0:
		return out
	var sub := RandomNumberGenerator.new()
	for r in rolls:
		# The main rng draws exactly two numbers per roll, whatever
		# happens next: the pick and a seed for this roll's own sub-rng
		# (gate, count, conditions). A gate outcome can therefore never
		# shift later rolls — world age only removes items.
		var e: Dictionary = table.entries[pick_weighted(weights, total, rng.randf())]
		sub.seed = rng.randi()
		var gate := sub.randf()
		if gate >= effective_chance(e, world_age_days):
			continue
		var mn := int(e.get("min_count", 1))
		var mx := maxi(int(e.get("max_count", mn)), mn)
		var count := sub.randi_range(mn, mx)
		var id := StringName(e.get("item_id", &""))
		var data := ItemDB.get_item(id)
		if data == null:
			continue
		if data.has_condition():
			for i in count:
				var f := lerpf(table.condition_min, table.condition_max, sub.randf())
				out.append({"id": id, "count": 1, "condition": clampi(int(round(f * data.max_condition)), 1, data.max_condition)})
		else:
			_merge(out, id, count)
	return out


## Index of the entry that [r] (0..1) falls into.
static func pick_weighted(weights: PackedFloat64Array, total: float, r: float) -> int:
	var x := clampf(r, 0.0, 0.999999) * total
	var last := 0
	for i in weights.size():
		if weights[i] <= 0.0:
			continue
		last = i
		if x < weights[i]:
			return i
		x -= weights[i]
	return last


## Seed for a container: stable across runs and machines (String.hash is
## deterministic) from the world seed and the container's stable id.
static func seed_for(world_seed: int, stable_id: String) -> int:
	return ("%d|%s" % [world_seed, stable_id]).hash()


## Table ids to try, most specific first, for a container of type
## [container] in a room of type [room] in a building of type [building]
## (any may be empty). Fallback chain container → room → default:
##   "<b>/<r>/<c>", "<r>/<c>", "<b>/<c>", "<r>_<c>", "<b>_<c>", "<c>",
##   "<b>/<r>", "<r>", "<b>", "default".
static func table_candidates(building: StringName, room: StringName, container: StringName) -> Array[String]:
	var b := String(building)
	var r := String(room)
	var c := String(container)
	var out: Array[String] = []
	if c != "":
		if b != "" and r != "":
			out.append("%s/%s/%s" % [b, r, c])
		if r != "":
			out.append("%s/%s" % [r, c])
		if b != "":
			out.append("%s/%s" % [b, c])
		if r != "":
			out.append("%s_%s" % [r, c])
		if b != "":
			out.append("%s_%s" % [b, c])
		out.append(c)
	if r != "":
		if b != "":
			out.append("%s/%s" % [b, r])
		out.append(r)
	if b != "":
		out.append(b)
	out.append("default")
	return out


static func _merge(out: Array[Dictionary], id: StringName, count: int) -> void:
	for e in out:
		if e.id == id and e.condition == -1:
			e.count += count
			return
	out.append({"id": id, "count": count, "condition": -1})
