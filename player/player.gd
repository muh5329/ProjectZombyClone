class_name Player
extends Character
## The player-controlled survivor. Thin: registers itself and hosts the
## controller / interaction / combat / equipment child nodes. Gameplay
## logic lives in those nodes and in the shared Character/components.
##
## Carrying (Round 6):
## - [inventory]: the main inventory, a hard-capped ItemContainer
##   (profile.inventory_capacity, 20 kg).
## - Equipment child: hands (primary / secondary, two-handers take both),
##   back (a bag whose contents are extra storage), hotbar 1-3. Equipped
##   items are out of the inventory.
## - Encumbrance child: carried weight → ok / light / heavy / overloaded
##   → speed, stamina drain, footstep noise, sprint.
## Item verbs the UI / input call (all return {ok, reason?} and surface
## refusals via EventBus.interaction_refused): pick_up_item, equip_item,
## unequip_item, move_item, drop_item, split_item, use_item, use_hotbar,
## cycle_weapon. Anything leaving the player asks can_release_item first.

## Items granted on _ready as {id: count} (debug starts / tests).
@export var starting_items: Dictionary = {}

var inventory: ItemContainer = ItemContainer.new(20.0)

@onready var combat: MeleeCombat = get_node_or_null("Combat")
@onready var equipment: Equipment = get_node_or_null("Equipment")
@onready var encumbrance: Encumbrance = get_node_or_null("Encumbrance")
## Round 7: eating / drinking (child "Consume") and sleep / rest ("Rest").
@onready var consume: ConsumeAction = get_node_or_null("Consume")
@onready var rest: RestComponent = get_node_or_null("Rest")


func _enter_tree() -> void:
	# _enter_tree (not _ready) so re-parenting / chunk streaming re-registers.
	add_to_group(&"player")
	GameManager.register_player(self)


func _exit_tree() -> void:
	GameManager.unregister_player(self)


## Worn footwear (an equipped item tagged &"shoes") protects against
## broken glass (GlassShards). No shoes exist yet: barefoot-ish survivor.
func has_foot_protection() -> bool:
	if equipment == null:
		return false
	for it in equipment.equipped_items():
		if it != null and it.data != null and it.data.has_tag(&"shoes"):
			return true
	return false


func _ready() -> void:
	super._ready()
	if profile:
		inventory.capacity = profile.inventory_capacity
	if equipment:
		equipment.character = self
		equipment.contents_changed.connect(_on_carried_changed)
	elif not inventory.changed.is_connected(_on_carried_changed):
		inventory.changed.connect(_on_carried_changed)
	if encumbrance:
		encumbrance.setup(self)
	for id in starting_items:
		inventory.add_id(StringName(id), int(starting_items[id]))


func _on_carried_changed() -> void:
	if encumbrance:
		encumbrance.mark_dirty()  # coalesced: one recompute per frame
	EventBus.inventory_changed.emit(self)


# --- Queries ---------------------------------------------------------------------

## Carried storage: main inventory (+ the worn bag's contents).
func carried_storage() -> Array[ItemContainer]:
	if equipment:
		return equipment.storage()
	var out: Array[ItemContainer] = [inventory]
	return out


## True for the player's own containers (storage and equipment slots).
func owns_container(c: ItemContainer) -> bool:
	if equipment:
		return equipment.owns_container(c)
	return c == inventory


## True when [item] is on the player (equipped or stored).
func carries(item: ItemInstance) -> bool:
	return item != null and item.stack > 0 and owns_container(item.owner_container())


## Carried weight (kg) as encumbrance sees it.
func carried_weight() -> float:
	return encumbrance.weight if encumbrance else inventory.total_weight()


## {ok, reason} — may [item] leave where it is right now? Every path that
## takes something out of the player's hands / pack (container put,
## Transfer All, unequip, drop) asks this first: the equipped or swung
## weapon cannot go mid-swing (it would dodge its wear / vanish from the
## swing).
func can_release_item(item: ItemInstance) -> Dictionary:
	if item == null:
		return {"ok": false, "reason": "Nothing there"}
	if combat and combat.is_swinging() and (item == combat.equipped or item == combat.swing.item):
		return {"ok": false, "reason": "Mid-swing"}
	if is_dead():
		return {"ok": false, "reason": "Dead"}
	return {"ok": true}


## Carried, unbroken weapons (hands + storage), in creation order.
func held_weapons() -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	var sources: Array = []
	if equipment:
		sources.append_array(equipment.hand_items())
	for c in carried_storage():
		sources.append_array(c.items)
	for it in sources:
		if it.is_weapon() and not it.is_broken() and not out.has(it):
			out.append(it)
	out.sort_custom(func(a: ItemInstance, b: ItemInstance): return a.uid < b.uid)
	return out


# --- Verbs -------------------------------------------------------------------------

## Pick up [item] (WorldItem calls this): into the main inventory, or —
## when that is full — straight into empty hands (weapons / tools) or
## onto an empty back (bags). Auto-equips a weapon when the hands are
## empty.
func pick_up_item(item: ItemInstance) -> Dictionary:
	if item == null or item.data == null:
		return {"ok": false, "reason": "Nothing there"}
	if is_dead() or is_busy:
		return {"ok": false, "reason": "Busy"}
	var r := inventory.add(item)
	if not r.ok and equipment:
		var slot := Equipment.default_slot(item)
		if equipment.item_in(slot) == null and Equipment.slot_rule(item, slot) == "":
			var e := equipment.equip(item, slot)
			if e.ok:
				r = {"ok": true, "equipped": slot}
	if not r.ok:
		return r
	EventBus.item_picked_up.emit(self, {"id": item.id(), "name": item.display_name()})
	if equipment and equipment.primary() == null and item.is_weapon() and inventory.has(item):
		equipment.equip(item, Equipment.PRIMARY)
	elif combat and not equipment and combat.equipped == null and item.is_weapon():
		combat.equip(item)
	return {"ok": true}


## Equip [item] (slot &"" = its default: bags on the back, else hands).
func equip_item(item: ItemInstance, slot: StringName = &"") -> Dictionary:
	if equipment == null:
		return _refuse("Can't equip")
	if is_dead() or is_busy:
		return _refuse("Busy")
	return _report(equipment.equip(item, slot))


## Put an equipped item away. Taking off the worn bag when there is no
## room for it drops it at the feet instead (PZ), with a notice.
func unequip_item(item: ItemInstance) -> Dictionary:
	if equipment == null:
		return _refuse("Can't unequip")
	if is_dead() or is_busy:
		return _refuse("Busy")
	var r := equipment.unequip(item)
	if not r.ok and r.reason == Equipment.REASON_NO_ROOM and item != null and item == equipment.back_bag():
		var d := drop_item(item)
		if d.ok:
			EventBus.interaction_refused.emit(self, null, "No room: dropped %s at your feet" % item.display_name())
			return {"ok": true, "dropped": true, "world_item": d.world_item}
	return _report(r)


## Move [count] (< 0 = all) of [item] between the player's own
## containers (inventory ↔ worn bag; out of a slot unequips).
func move_item(item: ItemInstance, to: ItemContainer, count: int = -1) -> Dictionary:
	if item == null or not carries(item):
		return _refuse("Not here")
	if not owns_container(to) or to.equipment_slot != &"":
		return _refuse("Can't put it there")
	var from := item.owner_container()
	if from == to:
		return {"ok": false, "reason": "Already there"}
	var rel := can_release_item(item)
	if not rel.ok:
		return _refuse(String(rel.reason))
	return _report(from.transfer_to(to, item, count))


## Drop [count] (< 0 = the stack) of [item] at the player's feet as a
## WorldItem (layer 4) that stays in the scene.
func drop_item(item: ItemInstance, count: int = -1) -> Dictionary:
	if item == null or not carries(item):
		return _refuse("Not here")
	if is_dead():
		return _refuse("Dead")
	if is_busy:
		return _refuse("Busy")
	var rel := can_release_item(item)
	if not rel.ok:
		return _refuse(String(rel.reason))
	var from := item.owner_container()
	var inst := from.remove(item, count)
	if inst == null:
		return _refuse("Nothing there")
	var w := WorldItem.drop(inst, self)
	EventBus.item_dropped.emit(self, {"id": inst.id(), "name": inst.display_name(), "count": inst.stack})
	return {"ok": true, "world_item": w}


## Split half of a stack into a new stack in the same container.
func split_item(item: ItemInstance) -> Dictionary:
	if item == null or not carries(item):
		return _refuse("Not here")
	if item.stack < 2:
		return _refuse("Can't split one item")
	var out := item.owner_container().split_stack(item, item.stack / 2)
	return {"ok": out != null, "item": out}


## Use [item]: dressings bandage the worst wound; food / drink is eaten /
## drunk whole (Round 7; see consume_item for half portions).
func use_item(item: ItemInstance) -> Dictionary:
	if item == null or not carries(item):
		return _refuse("Not here")
	var med := item.data as MedicalData
	if med != null and med.bandage_quality > 0.0:
		if injuries == null:
			return _refuse("Can't bandage")
		return injuries.bandage_worst(item)
	if item.data is FoodData:
		return consume_item(item, 1.0)
	var why := ItemActions.use_block_reason(item.data)
	return _refuse(why if why != "" else "Can't use that")


## Eat / drink [portion] of [item] (1 = all that is left, 0.5 = half).
func consume_item(item: ItemInstance, portion: float = 1.0) -> Dictionary:
	if consume == null:
		return _refuse("Can't eat")
	return consume.start(item, portion)


## Hotbar key [index] (0-based): equip the assigned item / put it away.
func use_hotbar(index: int) -> Dictionary:
	if equipment == null:
		return _refuse("No hotbar")
	if is_dead() or is_busy:
		return _refuse("Busy")
	return _report(equipment.use_hotbar(index))


## X: fists → carried weapons (creation order) → fists.
func cycle_weapon() -> bool:
	if combat == null:
		return false
	if combat.is_swinging():
		# No swapping mid-swing (the swing would dodge its own wear).
		EventBus.attack_refused.emit(self, "Mid-swing")
		return false
	if equipment == null:
		var opts: Array = [null]
		opts.append_array(held_weapons())
		combat.equip(opts[(opts.find(combat.equipped) + 1) % opts.size()])
		return true
	var options: Array = [null]
	options.append_array(held_weapons())
	var cur := equipment.primary()
	var i := options.find(cur if cur != null and cur.is_weapon() else null)
	var next: ItemInstance = options[(i + 1) % options.size()]
	var r: Dictionary
	if next == null:
		r = equipment.unequip(Equipment.PRIMARY) if cur != null else {"ok": true}
	else:
		r = equipment.equip(next, Equipment.PRIMARY)
	if not r.ok:
		EventBus.attack_refused.emit(self, String(r.reason))
		return false
	return true


## MeleeCombat calls this when the equipped weapon breaks: it is gone.
func on_weapon_broken(item: ItemInstance) -> void:
	if equipment and equipment.destroy(item):
		return
	var c := item.owner_container()
	if c != null and owns_container(c):
		c.remove(item)


func _report(r: Dictionary) -> Dictionary:
	if not r.get("ok", false):
		EventBus.interaction_refused.emit(self, null, String(r.get("reason", "Can't")))
	return r


func _refuse(reason: String) -> Dictionary:
	EventBus.interaction_refused.emit(self, null, reason)
	return {"ok": false, "reason": reason}


# --- Save --------------------------------------------------------------------------

## Inventory + equipment (bags with their nested contents, hotbar refs).
func carried_to_dict() -> Dictionary:
	var d := {"inventory": inventory.to_dict()}
	if equipment:
		d["equipment"] = equipment.to_dict()
	return d


func carried_from_dict(d: Dictionary) -> void:
	inventory.from_dict(d.get("inventory", {}))
	if profile:
		inventory.capacity = profile.inventory_capacity
	if equipment and d.has("equipment"):
		equipment.from_dict(d.equipment)


# --- Whole-player save (Round 10, WorldSnapshot) --------------------------------------

## Position / facing, health, every stat (stamina, pain, infection,
## hunger, thirst, fatigue, sickness), wounds, needs, skills and
## everything carried. Saving is refused while busy (an item being eaten
## or a dressing being applied is out of its container), so no busy
## state is ever stored.
func save_state() -> Dictionary:
	var d := {
		"position": Saveable.vec3(global_position),
		"facing": movement.facing,
		"stats": stats.to_dict(),
		"carried": carried_to_dict(),
	}
	if health:
		d["health"] = health.to_dict()
	if injuries:
		d["injuries"] = injuries.to_dict()
	if needs:
		d["needs"] = needs.to_dict()
	var sk := SkillComponent.of(self)
	if sk:
		d["skills"] = sk.to_dict()
	return d


## Restore onto a FRESH player (the load flow reloads the map). Order
## matters: wounds / needs set the stamina cap before the stats values.
func load_state(d: Dictionary) -> void:
	if is_busy and busy_context != &"dead":
		cancel_busy()
	velocity = Vector3.ZERO
	global_position = Saveable.to_vec3(d.get("position"), global_position)
	var yaw := float(d.get("facing", movement.facing))
	movement.facing = yaw
	if visual:
		visual.rotation.y = yaw
	if d.has("carried"):
		carried_from_dict(d.carried)
	if injuries:
		injuries.restoring = true
	if injuries and d.has("injuries"):
		injuries.from_dict(d.injuries)
	if needs and d.has("needs"):
		needs.from_dict(d.needs)
	if d.has("stats"):
		stats.from_dict(d.stats)
	if needs and d.has("needs"):
		needs.from_dict(d.needs)  # settle levels on the final values
	var sk := SkillComponent.of(self)
	if sk and d.has("skills"):
		sk.from_dict(d.skills)
	if injuries:
		# Stage from the restored infection value, silently (no "You feel
		# feverish" for a state the player already had).
		injuries.infection_stage = InjuryComponent.infection_stage_for(stats.get_value(InjuryComponent.INFECTION), injuries.profile)
		injuries.restoring = false
		EventBus.injuries_changed.emit(self, injuries.summary())
	if health and d.has("health"):
		health.from_dict(d.health)
	if encumbrance:
		encumbrance.recompute()
