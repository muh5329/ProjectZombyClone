class_name ItemContainer
extends RefCounted
## Shared inventory model (pure data): a weight capacity and a list of
## ItemInstance stacks. Used by the player (`Player.inventory`), world
## containers (`LootContainer.inventory`), corpses and — in Round 6 —
## bags / equipment. Anything that owns one exposes it as `inventory`.
##
## - Stacking: an added item merges into existing stacks of the same id
##   up to ItemData.max_stack; items with a condition never stack.
## - Capacity is weight (kg); capacity < 0 = unlimited. Anything that
##   would exceed it is refused with reason "Too heavy" (Round 6 turns
##   the player's limit into encumbrance instead).
## - All mutators return result Dictionaries ({ok, reason?, moved?}) and
##   emit [signal changed] once per call that changed something.
## - to_dict()/from_dict() store ids + counts + condition for saves.
## Pure (no scene tree): unit-tested in tests/unit/test_inventory.gd.
## Mutators never exceed the capacity; the UI asks can_fit() / fit_count()
## beforehand to grey out rows.

signal changed

const EPS := 0.0001
const REASON_HEAVY := "Too heavy"
const REASON_ELSEWHERE := "Already in another container"

## Weight capacity in kg (< 0 = unlimited).
var capacity: float = -1.0
var items: Array[ItemInstance] = []


func _init(p_capacity: float = -1.0) -> void:
	capacity = p_capacity


# --- Queries -------------------------------------------------------------------

func total_weight() -> float:
	var w := 0.0
	for it in items:
		w += it.total_weight()
	return w


func free_weight() -> float:
	return INF if capacity < 0.0 else maxf(capacity - total_weight(), 0.0)


func is_empty() -> bool:
	return items.is_empty()


func has(item: ItemInstance) -> bool:
	return items.has(item)


## First stack of [id] (null when none).
func find(id: StringName) -> ItemInstance:
	for it in items:
		if it.id() == id:
			return it
	return null


## Every stack of [id].
func find_all(id: StringName) -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	for it in items:
		if it.id() == id:
			out.append(it)
	return out


## First stack for which [pred].call(item) is true.
func find_where(pred: Callable) -> ItemInstance:
	for it in items:
		if pred.call(it):
			return it
	return null


## Total number of items of [id] across stacks.
func count_of(id: StringName) -> int:
	var n := 0
	for it in items:
		if it.id() == id:
			n += it.stack
	return n


## Total number of items (not stacks).
func item_count() -> int:
	var n := 0
	for it in items:
		n += it.stack
	return n


## How many of [data] fit by weight (up to [wanted]).
func fit_count(data: ItemData, wanted: int) -> int:
	if data == null or wanted <= 0:
		return 0
	if capacity < 0.0 or data.weight <= 0.0:
		return wanted
	var free := capacity - total_weight()
	return clampi(int(floor((free + EPS) / data.weight)), 0, wanted)


## True when [count] of [data] fit by weight.
func can_fit(data: ItemData, count: int = 1) -> bool:
	return data != null and fit_count(data, count) >= count


## {ok, reason} for adding [count] of [data] (whole amount must fit).
func can_add(data: ItemData, count: int = 1) -> Dictionary:
	if data == null:
		return {"ok": false, "reason": "Nothing there"}
	if fit_count(data, count) < count:
		return {"ok": false, "reason": REASON_HEAVY}
	return {"ok": true}


## Grouped view for UIs: [{id, name, count, weight, data, stacks}] in
## first-seen order (identical ids collapse into one row).
func grouped() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var index := {}
	for it in items:
		var id := it.id()
		if not index.has(id):
			index[id] = out.size()
			out.append({"id": id, "name": it.display_name(), "count": 0, "weight": 0.0, "data": it.data, "stacks": []})
		var row: Dictionary = out[index[id]]
		row.count += it.stack
		row.weight += it.total_weight()
		row.stacks.append(it)
	return out


# --- Mutators ------------------------------------------------------------------

## Add [item] (its whole stack). Refused ("Too heavy") unless everything
## fits. The instance itself is stored when it cannot merge; merged
## instances are consumed (their stack goes into existing stacks).
func add(item: ItemInstance) -> Dictionary:
	if item == null or item.data == null or item.stack <= 0:
		return {"ok": false, "reason": "Nothing there"}
	if items.has(item):
		return {"ok": false, "reason": "Already here"}
	var holder := item.owner_container()
	if holder != null and holder != self:
		return {"ok": false, "reason": REASON_ELSEWHERE}
	var chk := can_add(item.data, item.stack)
	if not chk.ok:
		return chk
	var n := item.stack
	_insert(item)
	changed.emit()
	return {"ok": true, "moved": n}


## Add [count] new items of the ItemDB item [id] (tests, debug).
func add_id(id: StringName, count: int = 1, condition: int = -1) -> Dictionary:
	return add_new(ItemDB.get_item(id), count, condition)


## Add [count] new items of [data] (loot generation, tests).
func add_new(data: ItemData, count: int = 1, condition: int = -1) -> Dictionary:
	if data == null or count <= 0:
		return {"ok": false, "reason": "Nothing there"}
	return add(ItemInstance.new(data, condition, count))


## Remove up to [count] items from the stack [item] (count < 0 = all).
## Returns the removed items as an instance ([item] itself when the whole
## stack goes; it then belongs to no container), or null when [item] is
## not here or [count] is 0.
func remove(item: ItemInstance, count: int = -1) -> ItemInstance:
	var i := items.find(item)
	if i < 0 or count == 0:
		return null
	var out: ItemInstance
	if count < 0 or count >= item.stack:
		items.remove_at(i)
		item._set_owner_container(null)
		out = item
	else:
		out = item.split(count)
	changed.emit()
	return out


## Remove [count] items of [id] across stacks. Returns how many went.
func remove_id(id: StringName, count: int) -> int:
	var left := count
	for i in range(items.size() - 1, -1, -1):
		if left <= 0:
			break
		var it := items[i]
		if it.id() != id:
			continue
		var n := mini(left, it.stack)
		if n >= it.stack:
			items.remove_at(i)
			it._set_owner_container(null)
		else:
			it.stack -= n
		left -= n
	if left != count:
		changed.emit()
	return count - left


## Move up to [count] (< 0 = the whole stack) of [item] into [to]. Moves
## as many as fit by weight; refused ("Too heavy") only when none fit.
## Returns {ok, reason?, moved}.
func transfer_to(to: ItemContainer, item: ItemInstance, count: int = -1) -> Dictionary:
	if to == null or to == self:
		return {"ok": false, "reason": "Nowhere to put it", "moved": 0}
	if not items.has(item):
		return {"ok": false, "reason": "Not here", "moved": 0}
	var want := item.stack if count < 0 else mini(count, item.stack)
	if want <= 0:
		return {"ok": false, "reason": "Nothing there", "moved": 0}
	var n := to.fit_count(item.data, want)
	if n <= 0:
		return {"ok": false, "reason": REASON_HEAVY, "moved": 0}
	var moving := remove(item, n)
	to._insert(moving)
	to.changed.emit()
	return {"ok": true, "moved": n, "partial": n < want}


## Move every item of [id] (up to [count], < 0 = all) into [to].
func transfer_id(to: ItemContainer, id: StringName, count: int = -1) -> Dictionary:
	var moved := 0
	var left := count
	var reason := ""
	for it in find_all(id):
		if left == 0:
			break
		var r := transfer_to(to, it, left)
		moved += int(r.get("moved", 0))
		if left > 0:
			left -= int(r.get("moved", 0))
		if not r.ok or r.get("partial", false):
			reason = String(r.get("reason", REASON_HEAVY))
			break
	if moved == 0:
		return {"ok": false, "reason": reason if reason != "" else "Nothing there", "moved": 0}
	return {"ok": true, "moved": moved, "partial": reason != ""}


## Move everything that fits into [to] ("Loot All" / "Transfer All").
## Returns {ok, moved (items), left (items that did not fit), reason?}.
func transfer_all(to: ItemContainer) -> Dictionary:
	var moved := 0
	for it in items.duplicate():
		var r := transfer_to(to, it)
		moved += int(r.get("moved", 0))
	var left := item_count()
	var out := {"ok": moved > 0, "moved": moved, "left": left}
	if left > 0:
		out["reason"] = REASON_HEAVY
	elif moved == 0:
		out["reason"] = "Nothing there"
	return out


## Split [n] items off the stack [item] into a NEW stack right after it
## (same container, not merged back). Returns the new stack, or null when
## [item] is not here or n is not in 1..stack-1.
func split_stack(item: ItemInstance, n: int) -> ItemInstance:
	var i := items.find(item)
	if i < 0 or n < 1 or n >= item.stack:
		return null
	var out := item.split(n)
	items.insert(i + 1, out)
	out._set_owner_container(self)
	changed.emit()
	return out


func index_of(item: ItemInstance) -> int:
	return items.find(item)


func clear() -> void:
	if items.is_empty():
		return
	for it in items:
		it._set_owner_container(null)
	items.clear()
	changed.emit()


# --- Save ----------------------------------------------------------------------

## {capacity, items: [{id, count, condition}]} (ids resolved via ItemDB).
func to_dict() -> Dictionary:
	var list: Array = []
	for it in items:
		list.append({"id": String(it.id()), "count": it.stack, "condition": it.condition})
	return {"capacity": capacity, "items": list}


## Replace the contents from to_dict() data. Unknown ids and entries with
## a count <= 0 are skipped with a warning; the capacity is respected
## (what does not fit is dropped with a warning — never an over-full
## container). Capacity is kept unless the dict carries one.
func from_dict(d: Dictionary) -> void:
	for it in items:
		it._set_owner_container(null)
	items.clear()
	if d.has("capacity"):
		capacity = float(d.capacity)
	for e in d.get("items", []):
		var n := int(e.get("count", e.get("stack", 1)))
		if n <= 0:
			push_warning("ItemContainer.from_dict: skipping '%s' with count %d" % [str(e.get("id", "?")), n])
			continue
		var inst := ItemInstance.from_dict(e)
		if inst == null:
			push_warning("ItemContainer.from_dict: unknown item '%s'" % str(e.get("id", "?")))
			continue
		var fit := fit_count(inst.data, inst.stack)
		if fit < inst.stack:
			push_warning("ItemContainer.from_dict: %d × '%s' over capacity, dropped" % [inst.stack - fit, inst.id()])
			if fit <= 0:
				continue
			inst.stack = fit
		_insert(inst)
	changed.emit()


# --- Internals -----------------------------------------------------------------

## Merge [item] into existing stacks / append (no capacity check, no signal).
## Stored instances get this container as owner; a fully merged [item] is
## consumed (owner cleared).
func _insert(item: ItemInstance) -> void:
	item._set_owner_container(null)
	var data := item.data
	if data.is_stackable():
		var left := item.stack
		for it in items:
			if left <= 0:
				break
			if it.can_stack_with(item) and it.stack < data.max_stack:
				var n := mini(data.max_stack - it.stack, left)
				it.stack += n
				left -= n
		if left == 0:
			item.stack = 0  # fully merged: this instance is spent
		# The rest in chunks of max_stack; the last chunk reuses [item].
		while left > 0:
			var n := mini(left, data.max_stack)
			left -= n
			if left == 0:
				item.stack = n
				_append(item)
			else:
				_append(ItemInstance.new(data, item.condition, n))
	elif item.stack > 1:
		# Non-stackable items live one per instance.
		for i in item.stack - 1:
			_append(ItemInstance.new(data, item.condition, 1))
		item.stack = 1
		_append(item)
	else:
		_append(item)


func _append(item: ItemInstance) -> void:
	items.append(item)
	item._set_owner_container(self)
