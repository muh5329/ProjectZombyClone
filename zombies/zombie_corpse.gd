class_name ZombieCorpse
extends LootContainer
## What a dead zombie leaves behind: a static body on layer 4
## (interactables) only — it blocks nobody and is walked over — with the
## ZombieVisual (its CharacterModel falls into the z_death pose and keeps
## it). Round 5: it is a LootContainer of type
## &"zombie_corpse": "Search corpse" rolls the pockets lazily from the
## data/loot/zombie_corpse table (seeded by the world seed + the zombie's
## persist id "corpse/<ai_seed>"). Group "corpse".


var killer: Node = null
## The dead zombie's look seed (Round 10: a restored corpse rebuilds the
## same person from it).
var look_seed: int = 0
## Heading it fell with (radians; kept exactly for the save).
var yaw: float = 0.0


func _init() -> void:
	super._init()
	container_type = &"zombie_corpse"
	display_name = "Zombie corpse"
	capacity = 25.0
	prompt_height = 0.4
	search_label = "Search corpse"
	search_noise_radius = 0.0
	static_saveable = false
	room_type = &""
	building_type = &""


func _ready() -> void:
	add_to_group(&"corpse")
	collision_layer = LAYER_INTERACTABLES
	collision_mask = 0
	if get_node_or_null("Shape") == null:
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		var box := BoxShape3D.new()
		# The model falls face down along -Z (head ~0.8 m ahead of the feet).
		box.size = Vector3(0.7, 0.5, 1.9)
		shape.shape = box
		shape.position = Vector3(0, 0.25, -0.1)
		add_child(shape)
	super._ready()


## Adopt the zombie's visual node (re-parented) and collapse it.
func adopt_visual(v: ZombieVisual) -> void:
	if v.get_parent() != null:
		v.get_parent().remove_child(v)
	add_child(v)
	v.transform = Transform3D.IDENTITY
	v.rotation.y = 0.0
	v.collapse()


func take_damage(_amount: float, _source: Node = null, _info: Dictionary = {}) -> Dictionary:
	return {"ok": false, "reason": "Already dead", "health": 0.0}


func is_dead() -> bool:
	return true


# --- Save (Round 10, WorldSnapshot spawn records) ----------------------------------------

## The corpse as a spawn record: id (keys the pockets' loot seed), look,
## where it lies, its pose and the container state (searched + contents).
func save_record() -> Dictionary:
	var v := get_node_or_null("Visual") as ZombieVisual
	var pose := "death"
	if v != null and v.model != null and v.model.current == &"z_knockdown":
		pose = "knockdown"
	return {
		"persist_id": persist_id, "seed": look_seed,
		"position": Saveable.vec3(global_position), "yaw": yaw,
		"pose": pose, "container": to_dict(),
	}


## Re-create a corpse from save_record() under [parent]: a fresh
## ZombieVisual with the same look, snapped to the final pose.
static func restore(parent: Node, d: Dictionary) -> ZombieCorpse:
	var c := ZombieCorpse.new()
	c.persist_id = String(d.get("persist_id", ""))
	c.look_seed = int(d.get("seed", 0))
	c.yaw = float(d.get("yaw", 0.0))
	c.name = "Corpse"
	parent.add_child(c, true)
	c.global_transform = Transform3D(Basis(Vector3.UP, c.yaw), Saveable.to_vec3(d.get("position")))
	var v := ZombieVisual.new()
	v.name = "Visual"
	v.seed_override = c.look_seed if c.look_seed != 0 else hash(c.persist_id) | 1
	c.add_child(v)
	v.collapse_now(String(d.get("pose", "death")) == "knockdown")
	if d.has("container"):
		c.from_dict(d.container)
	return c
