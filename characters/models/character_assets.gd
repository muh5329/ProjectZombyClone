class_name CharacterAssets
extends Node
## Shared resources for procedural people: one Skin, one AnimationLibrary,
## the body / eye / hit materials, the outfit pool, typed mesh cache keyed
## by Appearance.key() and the stratified zombie look table (so 200
## zombies share ≤ ZOMBIE_VARIANTS meshes). Lives as a node
## "CharacterAssets" under the scene root (added deferred) — never in
## statics: resources held by a script at exit are reported as leaks.
## Vehicles have their own VehicleAssets.

const NODE_NAME := &"CharacterAssets"
const OUTFIT_DIR := "res://data/characters/outfits"
## Zombies pick one of this many pre-built looks (mesh sharing / build time).
const ZOMBIE_VARIANTS := 48
## Every outfit a zombie can wear gets at least this many looks.
const MIN_VARIANTS_PER_OUTFIT := 2
const TINT_COLORS := {
	&"normal": Color(0.06, 0.05, 0.04),
	&"alert": Color(0.95, 0.8, 0.25),
	&"hostile": Color(0.95, 0.12, 0.08),
	&"flash": Color(1.0, 0.97, 0.9),
	&"dead": Color(0.05, 0.05, 0.05),
}
const TINT_GLOW := {&"alert": 0.8, &"hostile": 1.6, &"flash": 2.0}
## Hit tint: the vertex colours pulled 30 % toward this red (albedo
## multiply + a little emission), body surface only.
const HIT_TINT := Color(0.9, 0.2, 0.15)
const HIT_TINT_AMOUNT := 0.3

var skin: Skin
var library: AnimationLibrary
var body_material: StandardMaterial3D
var outfits: Array[Outfit] = []
## Meshes built so far (perf report / tests).
var meshes_built: int = 0
var _eye_materials: Dictionary[StringName, StandardMaterial3D] = {}
var _hit_material: StandardMaterial3D
var _meshes: Dictionary[String, ArrayMesh] = {}
var _zombie_appearances: Dictionary[int, Appearance] = {}
var _outfit_by_id: Dictionary[StringName, Outfit] = {}
## Variant index → outfit (stratified, built once).
var _variant_outfits: Array[Outfit] = []
var _ready_done: bool = false

static var _instance: CharacterAssets = null


## The shared node (created on first use; added to the root deferred so
## it works while a scene is being set up).
static func of(tree: SceneTree) -> CharacterAssets:
	if is_instance_valid(_instance) and not _instance.is_queued_for_deletion():
		return _instance
	var root := tree.root
	var n := root.get_node_or_null(NodePath(NODE_NAME)) as CharacterAssets
	if n == null:
		n = CharacterAssets.new()
		n.name = NODE_NAME
		root.add_child.call_deferred(n)
	_instance = n
	return n


func _init() -> void:
	_ensure()


func _ensure() -> void:
	if _ready_done:
		return
	_ready_done = true
	skin = HumanoidBuilder.build_skin()
	library = CharacterAnimations.build_library()
	body_material = StandardMaterial3D.new()
	body_material.vertex_color_use_as_albedo = true
	body_material.vertex_color_is_srgb = true
	body_material.roughness = 0.92
	_load_outfits()
	_variant_outfits = stratify(zombie_outfits(), ZOMBIE_VARIANTS, MIN_VARIANTS_PER_OUTFIT)


func _load_outfits() -> void:
	outfits.clear()
	var files := DirAccess.get_files_at(OUTFIT_DIR)
	files.sort()
	for f in files:
		var fname := f.trim_suffix(".remap")
		if not fname.ends_with(".tres"):
			continue
		var o := load("%s/%s" % [OUTFIT_DIR, fname]) as Outfit
		if o != null:
			outfits.append(o)
			_outfit_by_id[o.id] = o


func outfit(id: StringName) -> Outfit:
	return _outfit_by_id.get(id) as Outfit


## Outfits that zombies can wear (zombie_weight > 0).
func zombie_outfits() -> Array[Outfit]:
	var out: Array[Outfit] = []
	for o in outfits:
		if o.zombie_weight > 0.0:
			out.append(o)
	return out


## Pure: [n] slots over [pool] — every outfit gets [min_each], the rest go
## by zombie_weight (largest remainder), interleaved so neighbouring
## variants differ.
static func stratify(pool: Array[Outfit], n: int, min_each: int) -> Array[Outfit]:
	var out: Array[Outfit] = []
	if pool.is_empty():
		return out
	var counts: Array[int] = []
	var total_w := 0.0
	for o in pool:
		counts.append(min_each)
		total_w += o.zombie_weight
	var left := n - min_each * pool.size()
	if left > 0 and total_w > 0.0:
		var rem: Array = []
		var given := 0
		for i in pool.size():
			var share := float(left) * pool[i].zombie_weight / total_w
			counts[i] += int(floor(share))
			given += int(floor(share))
			rem.append([share - floor(share), i])
		rem.sort_custom(func(a, b): return a[0] > b[0])
		for k in left - given:
			counts[rem[k % rem.size()][1]] += 1
	# Round-robin interleave.
	var more := true
	while more:
		more = false
		for i in pool.size():
			if counts[i] > 0:
				out.append(pool[i])
				counts[i] -= 1
				more = true
	return out


## Pure: which zombie look a spawn seed maps to (hashed — spawner seeds
## are all odd, so a plain modulo would skip half the looks).
static func variant_for_seed(seed_value: int, n: int = ZOMBIE_VARIANTS) -> int:
	return posmod(hash(seed_value), n)


## Pure: height variation for a zombie seed (not baked into the shared
## mesh: twins of one look still differ in height).
static func height_for_seed(seed_value: int) -> float:
	return 0.94 + float(posmod(hash(seed_value * 31 + 7), 1000)) / 1000.0 * 0.11


## Shared mesh for [app] (built on first use).
func mesh_for(app: Appearance) -> ArrayMesh:
	var k := app.key()
	if _meshes.has(k):
		return _meshes[k]
	var m := HumanoidBuilder.build_mesh(app)
	m.surface_set_material(HumanoidBuilder.SURFACE_BODY, body_material)
	m.surface_set_material(HumanoidBuilder.SURFACE_EYES, eye_material(&"normal"))
	_meshes[k] = m
	meshes_built += 1
	return m


func mesh_count() -> int:
	return _meshes.size()


## The zombie look for a spawn seed (one of ZOMBIE_VARIANTS).
func zombie_appearance(seed_value: int) -> Appearance:
	return zombie_variant(variant_for_seed(seed_value))


## Look number [v] (0..ZOMBIE_VARIANTS-1): stratified outfit + seeded
## skin / hair / decay.
func zombie_variant(v: int) -> Appearance:
	v = posmod(v, ZOMBIE_VARIANTS)
	if _zombie_appearances.has(v):
		return _zombie_appearances[v]
	var pool: Array[Outfit] = []
	if not _variant_outfits.is_empty():
		pool.append(_variant_outfits[v % _variant_outfits.size()])
	var a := Appearance.random(v * 7919 + 17, pool, true)
	_zombie_appearances[v] = a
	return a


## Eye material per mood (dark sockets when calm, glowing when alert /
## hostile — the subtle PZ-style state tell).
func eye_material(t: StringName) -> StandardMaterial3D:
	if _eye_materials.has(t):
		return _eye_materials[t]
	var m := StandardMaterial3D.new()
	var c: Color = TINT_COLORS.get(t, TINT_COLORS[&"normal"])
	m.albedo_color = c
	if TINT_GLOW.has(t):
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = TINT_GLOW[t]
	_eye_materials[t] = m
	return m


## Hit tint for the body surface: keeps the vertex colours, pulled toward
## HIT_TINT (not a flat salmon override).
func hit_material() -> StandardMaterial3D:
	if _hit_material == null:
		_hit_material = body_material.duplicate() as StandardMaterial3D
		_hit_material.albedo_color = Color.WHITE.lerp(HIT_TINT, HIT_TINT_AMOUNT)
		_hit_material.emission_enabled = true
		_hit_material.emission = HIT_TINT
		_hit_material.emission_energy_multiplier = 0.15
	return _hit_material
