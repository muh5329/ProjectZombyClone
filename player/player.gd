class_name Player
extends Character
## The player-controlled survivor. Thin: registers itself and hosts the
## controller / interaction / combat child nodes. Gameplay logic lives in
## those nodes and in the shared Character/components.
##
## Round 5: carried items live in [inventory] (an ItemContainer,
## [inventory_capacity] kg; refusals say "Too heavy"). Weapons are
## equipped from it; X cycles fists → carried weapons; a weapon that
## leaves the inventory leaves the hands. Round 6 adds equipment slots,
## bags and encumbrance on top.

## Carrying capacity in kg (Round 6 turns this into encumbrance).
@export var inventory_capacity: float = 15.0
## Items granted on _ready as {id: count} (debug starts / tests).
@export var starting_items: Dictionary = {}

var inventory: ItemContainer = ItemContainer.new(15.0)

@onready var combat: MeleeCombat = get_node_or_null("Combat")


func _enter_tree() -> void:
	# _enter_tree (not _ready) so re-parenting / chunk streaming re-registers.
	add_to_group(&"player")
	GameManager.register_player(self)


func _exit_tree() -> void:
	GameManager.unregister_player(self)


func _ready() -> void:
	super._ready()
	inventory.capacity = inventory_capacity
	if not inventory.changed.is_connected(_on_inventory_changed):
		inventory.changed.connect(_on_inventory_changed)
	for id in starting_items:
		inventory.add_id(StringName(id), int(starting_items[id]))


func _on_inventory_changed() -> void:
	if combat and combat.equipped != null and not inventory.has(combat.equipped):
		combat.equip(null)
	EventBus.inventory_changed.emit(self)


## Pick up [item] (WorldItem calls this). Refused "Too heavy" when it
## does not fit. Auto-equips a weapon when the hands are empty.
func pick_up_item(item: ItemInstance) -> Dictionary:
	if item == null or item.data == null:
		return {"ok": false, "reason": "Nothing there"}
	if is_dead() or is_busy:
		return {"ok": false, "reason": "Busy"}
	var r := inventory.add(item)
	if not r.ok:
		return r
	EventBus.item_picked_up.emit(self, {"id": item.id(), "name": item.display_name()})
	if combat and combat.equipped == null and item.is_weapon() and inventory.has(item):
		combat.equip(item)
	return {"ok": true}


## {ok, reason} — may [item] leave the inventory right now? Every path
## that takes something out of the player's hands / pack (container put,
## Transfer All, future drop) asks this first: the equipped or swung
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


## Carried, unbroken weapons in inventory order.
func held_weapons() -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	for it in inventory.items:
		if it.is_weapon() and not it.is_broken():
			out.append(it)
	return out




## X: fists → first carried weapon → … → fists.
func cycle_weapon() -> bool:
	if combat == null:
		return false
	if combat.is_swinging():
		# No swapping mid-swing (the swing would dodge its own wear).
		EventBus.attack_refused.emit(self, "Mid-swing")
		return false
	var options: Array = [null]
	options.append_array(held_weapons())
	var i := options.find(combat.equipped)
	combat.equip(options[(i + 1) % options.size()])
	return true


## MeleeCombat calls this when the equipped weapon breaks: it is dropped
## (removed from the inventory).
func on_weapon_broken(item: ItemInstance) -> void:
	if inventory.has(item):
		inventory.remove(item)
