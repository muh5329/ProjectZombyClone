extends "res://tests/test_case.gd"
## Round 8.5: procedural people (HumanoidBuilder / Appearance / Outfit /
## CharacterAnimations / animator clip choice) and vehicles
## (VehicleBuilder / VehicleData). Pure: no scene needed.

const OUTFIT_DIR := "res://data/characters/outfits"
const VEHICLE_DIR := "res://data/vehicles"
const REQUIRED_OUTFITS: Array[StringName] = [&"police_officer", &"firefighter", &"construction_worker",
	&"doctor", &"nurse_scrubs", &"jogger", &"office_worker", &"player_survivor"]
const REQUIRED_CLIPS: Array[StringName] = [&"idle", &"walk", &"jog", &"sprint", &"sneak", &"sneak_idle",
	&"windup_2h", &"strike_2h", &"windup_1h", &"strike_1h", &"windup_punch", &"strike_punch",
	&"windup_shove", &"strike_shove", &"climb", &"eat", &"search", &"bandage", &"sit", &"sleep", &"death", &"hit",
	&"z_idle", &"z_walk", &"z_chase", &"z_attack", &"z_bang", &"z_knockdown", &"z_getup", &"z_death", &"z_hit"]


func _load_dir(dir: String) -> Array:
	var out := []
	var files := DirAccess.get_files_at(dir)
	files.sort()
	for f in files:
		var n := f.trim_suffix(".remap")
		if n.ends_with(".tres"):
			out.append(load("%s/%s" % [dir, n]))
	return out


func _human(o: Outfit, skin_idx: int = 1) -> Appearance:
	var a := Appearance.new()
	a.outfit = o
	a.skin = Appearance.SKIN_TONES[skin_idx]
	a.hair_style = &"short"
	return a


## Colours of the body-surface vertices bound to [bone].
func _bone_colors(mesh: ArrayMesh, bone: StringName) -> Array[Color]:
	var arr := mesh.surface_get_arrays(HumanoidBuilder.SURFACE_BODY)
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var bi := HumanoidBuilder.bone_index(bone)
	var out: Array[Color] = []
	for v in cols.size():
		if bones[v * 4] == bi:
			out.append(cols[v])
	return out


func _has_color(cols: Array[Color], c: Color, tol: float = 0.01) -> bool:
	for k in cols:
		if absf(k.r - c.r) < tol and absf(k.g - c.g) < tol and absf(k.b - c.b) < tol:
			return true
	return false


# --- People --------------------------------------------------------------------

func test_skeleton_bones() -> void:
	var sk := HumanoidBuilder.build_skeleton()
	check_eq(sk.get_bone_count(), 17, "17 bones")
	check_eq(sk.get_bone_parent(sk.find_bone(&"hand_r")), sk.find_bone(&"forearm_r"), "hand → forearm")
	check_eq(sk.get_bone_parent(sk.find_bone(&"head")), sk.find_bone(&"neck"), "head → neck")
	check_eq(sk.get_bone_parent(sk.find_bone(&"thigh_l")), sk.find_bone(&"hips"), "thigh → hips")
	var head_y := sk.get_bone_global_rest(sk.find_bone(&"head")).origin.y
	check(head_y > 1.45 and head_y < 1.65, "neck/head joint at a realistic height (%.2f)" % head_y)
	check_gt(sk.get_bone_global_rest(sk.find_bone(&"upperarm_r")).origin.x, 0.1, "right arm on +X")
	var skin := HumanoidBuilder.build_skin()
	check_eq(skin.get_bind_count(), 17, "one bind per bone")
	sk.free()


func test_outfits_valid_and_varied() -> void:
	var outfits := _load_dir(OUTFIT_DIR)
	check(outfits.size() >= 10, "≥ 10 outfits (%d)" % outfits.size())
	var ids := {}
	for o: Outfit in outfits:
		check(o.validate().is_empty(), "%s valid %s" % [o.id, o.validate()])
		check(not ids.has(o.id), "unique id %s" % o.id)
		ids[o.id] = true
	for r in REQUIRED_OUTFITS:
		check(ids.has(r), "has outfit %s" % r)
	var zombie_pool := outfits.filter(func(o): return o.zombie_weight > 0.0)
	check(zombie_pool.size() >= 10, "≥ 10 outfits in the zombie pool")
	check(not zombie_pool.any(func(o): return o.id == &"player_survivor"), "the player's outfit is not worn by zombies")


func test_triangle_budget_and_skinning() -> void:
	for o: Outfit in _load_dir(OUTFIT_DIR):
		for z in [false, true]:
			var a := Appearance.random(7, [o], z)
			var mesh := HumanoidBuilder.build_mesh(a)
			var tris := HumanoidBuilder.triangle_count(mesh)
			check(tris >= 300 and tris <= 800, "%s%s: %d tris within 300..800" % [o.id, " (zombie)" if z else "", tris])
			check_eq(mesh.get_surface_count(), 2, "body + eyes surfaces")
			var arr := mesh.surface_get_arrays(0)
			check(arr[Mesh.ARRAY_BONES] != null and arr[Mesh.ARRAY_WEIGHTS] != null, "skinned")
			var aabb := mesh.get_aabb()
			check(aabb.size.y > 1.65 and aabb.size.y < 1.95, "about 1.75 m tall (%.2f)" % aabb.size.y)


func test_outfit_application() -> void:
	var tee := Outfit.new()
	tee.id = &"t"
	tee.shirt_color = Color(0.9, 0.1, 0.1)
	tee.short_sleeves = true
	tee.pants_color = Color(0.1, 0.1, 0.8)
	var jacket := Outfit.new()
	jacket.id = &"j"
	jacket.has_jacket = true
	jacket.jacket_color = Color(0.1, 0.7, 0.1)
	var a := _human(tee)
	var m1 := HumanoidBuilder.build_mesh(a)
	check(_has_color(_bone_colors(m1, &"chest"), HumanoidBuilder.cloth_color(tee.shirt_color)), "shirt colour on the chest")
	check(_bone_colors(m1, &"forearm_r").all(func(c): return absf(c.r - a.skin.r) < 0.01), "short sleeves: bare forearms")
	check(_has_color(_bone_colors(m1, &"thigh_l"), HumanoidBuilder.cloth_color(tee.pants_color)), "pants on the thighs")
	var m2 := HumanoidBuilder.build_mesh(_human(jacket))
	check(_has_color(_bone_colors(m2, &"forearm_r"), HumanoidBuilder.cloth_color(jacket.jacket_color)), "jacket sleeves to the wrist")
	check(_has_color(_bone_colors(m2, &"chest"), HumanoidBuilder.cloth_color(jacket.jacket_color)), "jacket on the chest")
	var cap := Outfit.new()
	cap.id = &"c"
	cap.hat = &"cap"
	cap.hat_color = Color(0.9, 0.9, 0.1)
	check(_has_color(_bone_colors(HumanoidBuilder.build_mesh(_human(cap)), &"head"), HumanoidBuilder.cloth_color(cap.hat_color)), "cap on the head")


func test_appearance_deterministic_per_seed() -> void:
	var outfits := _load_dir(OUTFIT_DIR)
	var a := Appearance.random(1234, outfits, true)
	var b := Appearance.random(1234, outfits, true)
	check_eq(a.key(), b.key(), "same seed → same look")
	var ma := HumanoidBuilder.build_mesh(a)
	var mb := HumanoidBuilder.build_mesh(b)
	check(ma.surface_get_arrays(0)[Mesh.ARRAY_COLOR] == mb.surface_get_arrays(0)[Mesh.ARRAY_COLOR], "identical vertex colours")
	var keys := {}
	for s in 20:
		keys[Appearance.random(s * 97 + 1, outfits, true).key()] = true
	check_gt(float(keys.size()), 15.0, "different seeds → varied looks")


func test_zombie_look() -> void:
	var o := Outfit.new()
	o.id = &"w"
	o.shirt_color = Color(0.9, 0.9, 0.9)
	var z := Appearance.random(3, [o], true)
	check(z.zombie, "zombie flag")
	var tone := Appearance.SKIN_TONES[0]
	check_lt(z.skin.s, tone.s, "desaturated skin")
	check(z.skin.g >= z.skin.r - 0.05, "grey-green, not pink (%s)" % z.skin)
	z.blood = 1.0
	var cols: Array[Color] = []
	for bone in [&"chest", &"spine"]:
		cols.append_array(_bone_colors(HumanoidBuilder.build_mesh(z), bone))
	check(cols.any(func(c): return c.r > c.g * 2.0 and c.r < 0.4), "blood on the clothes")
	# Torn sleeves: forearm shows skin even with long sleeves.
	var ls := Outfit.new()
	ls.id = &"ls"
	ls.short_sleeves = false
	ls.shirt_color = Color(0.2, 0.2, 0.9)
	var h := _human(ls)
	h.torn_right = true
	var fore := _bone_colors(HumanoidBuilder.build_mesh(h), &"forearm_r")
	check(_has_color(fore, h.skin), "torn sleeve shows the arm")


func test_animation_library() -> void:
	var lib := CharacterAnimations.build_library()
	for c in REQUIRED_CLIPS:
		check(lib.has_animation(c), "clip %s" % c)
	var walk := lib.get_animation(&"walk")
	check_eq(walk.get_track_count(), 18, "17 bone rotations + hips position")
	check_eq(walk.loop_mode, Animation.LOOP_LINEAR, "walk loops")
	check_eq(lib.get_animation(&"z_death").loop_mode, Animation.LOOP_NONE, "death holds its last frame")
	for c in CharacterAnimations.DESIGN_SPEED:
		check(lib.has_animation(c), "design speed clip %s exists" % c)
	# The lying poses really lie down: hips rotated ~90° and low.
	var death := lib.get_animation(&"death")
	var t := death.find_track(NodePath("Skeleton3D:hips"), Animation.TYPE_ROTATION_3D)
	var q: Quaternion = death.rotation_track_interpolate(t, death.length)
	check_lt(absf((Basis(q) * Vector3.UP).y), 0.3, "death clip ends lying")


func test_animator_clip_choice() -> void:
	check_eq(CharacterAnimator.locomotion_clip(MovementComponent.Mode.WALK, 0.0)[0], &"idle", "standing → idle")
	check_eq(CharacterAnimator.locomotion_clip(MovementComponent.Mode.SNEAK, 0.0)[0], &"sneak_idle", "crouched idle")
	check_eq(CharacterAnimator.locomotion_clip(MovementComponent.Mode.WALK, 2.0)[0], &"walk", "walk")
	check_eq(CharacterAnimator.locomotion_clip(MovementComponent.Mode.JOG, 3.4)[0], &"jog", "jog")
	check_eq(CharacterAnimator.locomotion_clip(MovementComponent.Mode.SPRINT, 5.6)[0], &"sprint", "sprint")
	check_near(CharacterAnimator.locomotion_clip(MovementComponent.Mode.JOG, 1.7)[1], 0.5, 0.01, "speed-scaled")
	check_eq(CharacterAnimator.busy_clip(&"climb"), &"climb", "climb")
	check_eq(CharacterAnimator.busy_clip(&"sleep"), &"sleep", "sleep")
	check_eq(CharacterAnimator.busy_clip(&"eat"), &"eat", "eat")
	var bat: WeaponData = load("res://data/items/weapons/baseball_bat.tres")
	var knife: WeaponData = load("res://data/items/weapons/kitchen_knife.tres")
	var shove: WeaponData = load("res://data/items/weapons/shove.tres")
	check_eq(CharacterAnimator.swing_clips(bat, false)[1], &"strike_2h", "bat: two-handed")
	check_eq(CharacterAnimator.swing_clips(knife, false)[1], &"strike_1h", "knife: one-handed")
	check_eq(CharacterAnimator.swing_clips(shove, false)[1], &"strike_shove", "shove")
	check_eq(CharacterAnimator.swing_clips(null, true)[1], &"strike_punch", "fists")
	check_eq(ZombieVisual.clip_for(&"idle", 0.0)[0], &"z_idle", "zombie idle")
	check_eq(ZombieVisual.clip_for(&"wander", 0.9)[0], &"z_walk", "zombie shamble")
	check_eq(ZombieVisual.clip_for(&"chase", 1.6)[0], &"z_chase", "zombie chase shamble")
	check_eq(ZombieVisual.clip_for(&"attack_door", 0.0)[0], &"z_bang", "door banging")


func test_zombie_looks_from_real_spawner_seeds() -> void:
	var assets := CharacterAssets.new()
	var pool := assets.zombie_outfits()
	var strat := CharacterAssets.stratify(pool, CharacterAssets.ZOMBIE_VARIANTS, CharacterAssets.MIN_VARIANTS_PER_OUTFIT)
	check_eq(strat.size(), CharacterAssets.ZOMBIE_VARIANTS, "%d looks" % CharacterAssets.ZOMBIE_VARIANTS)
	for o in pool:
		check(strat.count(o) >= 2, "%s has ≥ 2 looks" % o.id)
	for spawner_seed in [1337, 42]:
		var rng := RandomNumberGenerator.new()
		rng.seed = spawner_seed
		var variants := {}
		var worn := {}
		for i in 200:
			var zs := ZombieSpawner.next_seed(rng)
			variants[CharacterAssets.variant_for_seed(zs)] = true
			worn[assets.zombie_appearance(zs).outfit.id] = true
		check(variants.size() >= 30, "200 spawns → ≥ 30 distinct looks (%d, seed %d)" % [variants.size(), spawner_seed])
		for o in pool:
			check(worn.has(o.id), "outfit %s appears (seed %d)" % [o.id, spawner_seed])
	for r in [&"doctor", &"nurse_scrubs", &"firefighter", &"civ_tshirt_jeans"]:
		check(strat.any(func(o): return o.id == r), "%s in the zombie pool" % r)
	var heights := {}
	for i in 20:
		heights[snappedf(CharacterAssets.height_for_seed(i * 2 + 1), 0.001)] = true
	check_gt(float(heights.size()), 10.0, "heights vary per seed, not per look")
	assets.free()


func test_anim_lod_phase_distribution() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var hist := {}
	for i in 600:
		var ph := ZombieVisual.anim_phase(ZombieSpawner.next_seed(rng))
		hist[ph] = int(hist.get(ph, 0)) + 1
	check_eq(hist.size(), ZombieVisual.ANIM_DIVIDER_FAR, "every phase used")
	for ph in hist:
		check(hist[ph] >= 60 and hist[ph] <= 140, "phase %d even (%d / 600)" % [ph, hist[ph]])


func test_blood_limited_to_chest_and_sleeves() -> void:
	var o := Outfit.new()
	o.id = &"b"
	o.shirt_color = Color(0.7, 0.7, 0.7)
	o.short_sleeves = false
	var z := Appearance.random(11, [o], true)
	z.blood = 1.0
	var mesh := HumanoidBuilder.build_mesh(z)
	var arr := mesh.surface_get_arrays(0)
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var torso := 0
	var bloody := 0
	var legs_bloody := 0
	for t in cols.size() / 3:
		var c := cols[t * 3]
		var b := bones[t * 12]
		var is_blood := c.r > c.g * 1.8 and c.r < 0.4 and c.r > 0.12
		if b == HumanoidBuilder.bone_index(&"spine") or b == HumanoidBuilder.bone_index(&"chest"):
			torso += 1
			if is_blood:
				bloody += 1
		elif b == HumanoidBuilder.bone_index(&"thigh_l") or b == HumanoidBuilder.bone_index(&"shin_r"):
			if is_blood:
				legs_bloody += 1
	check_gt(float(bloody), 0.0, "some blood on the torso")
	check(float(bloody) / torso <= 0.35, "≤ 35 %% of the torso bloody (%.0f %%)" % (100.0 * bloody / torso))
	check_eq(legs_bloody, 0, "no blood on the legs")


func test_muted_palette() -> void:
	var o: Outfit = load("res://data/characters/outfits/civ_flannel.tres")
	var mesh := HumanoidBuilder.build_mesh(_human(o))
	for c in _bone_colors(mesh, &"chest"):
		check_lt(c.v, 0.76, "cloth value capped")
	var d: VehicleData = load("res://data/vehicles/police_sedan.tres")
	var vm := VehicleBuilder.build_mesh(d, 3)
	var vc: PackedColorArray = vm.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var maxv := 0.0
	for c in vc:
		maxv = maxf(maxv, c.v)
	check_lt(maxv, 0.76, "vehicle paint value capped (%.2f)" % maxv)


# --- Vehicles ---------------------------------------------------------------------

func test_vehicle_data_valid() -> void:
	var list := _load_dir(VEHICLE_DIR)
	check(list.size() >= 6, "≥ 6 vehicle types")
	var shapes := {}
	for d: VehicleData in list:
		check(d.validate().is_empty(), "%s valid %s" % [d.id, d.validate()])
		shapes[d.shape] = true
	for s in [&"sedan", &"wagon", &"pickup", &"van"]:
		check(shapes.has(s), "has a %s" % s)
	check(list.any(func(d): return d.livery == &"police" and d.light_bar), "police car with a light bar")
	check(list.any(func(d): return d.livery == &"fire"), "fire vehicle")


func test_vehicle_builder_dimensions() -> void:
	for d: VehicleData in _load_dir(VEHICLE_DIR):
		var mesh := VehicleBuilder.build_mesh(d, 5)
		var box := mesh.get_aabb()
		check_near(box.size.z, d.length, 0.3, "%s length" % d.id)
		check_near(box.size.x, d.width, 0.25, "%s width (mirrors)" % d.id)
		check(box.size.y >= d.roof_height - 0.01 and box.size.y <= d.roof_height + 0.2, "%s height %.2f" % [d.id, box.size.y])
		check_near(box.position.y, 0.0, 0.02, "%s sits on the ground" % d.id)
		var surf: Dictionary = mesh.get_meta(&"surfaces", {})
		for s in [&"body", &"glass", &"head", &"tail"]:
			check(surf.has(s), "%s has %s" % [d.id, s])
		check_eq(surf.has(&"beacon_a"), d.light_bar, "%s beacons only with a light bar" % d.id)
		var tris := VehicleBuilder.triangle_count(mesh)
		check(tris > 150 and tris < 1500, "%s low poly (%d tris)" % [d.id, tris])
		var col := VehicleBuilder.collision_size(d)
		check(col.z <= d.length + 0.01 and col.y <= d.roof_height + 0.01, "%s collider inside the body" % d.id)


func test_vehicle_variation_deterministic() -> void:
	var d: VehicleData = load("res://data/vehicles/sedan.tres")
	var a := VehicleBuilder.build_mesh(d, 42)
	var b := VehicleBuilder.build_mesh(d, 42)
	check(a.surface_get_arrays(0)[Mesh.ARRAY_COLOR] == b.surface_get_arrays(0)[Mesh.ARRAY_COLOR], "same seed → same car")
	var colours := {}
	for s in 12:
		colours[VehicleBuilder.variation_for(d, s * 13 + 1).color.to_html()] = true
	check_gt(float(colours.size()), 3.0, "palette variety")
	var pickup: VehicleData = load("res://data/vehicles/pickup.tres")
	var pm := VehicleBuilder.build_mesh(pickup, 1)
	# The open bed: no geometry near the belt line over the bed centre.
	var verts: PackedVector3Array = pm.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var bed_z := -pickup.length * 0.5 + (pickup.bed_start + 1.0) * 0.5 * pickup.length
	var covered := false
	for v in verts:
		if absf(v.x) < 0.3 and absf(v.z - bed_z) < 0.3 and v.y > pickup.belt_height - 0.2 and v.y < pickup.roof_height:
			covered = true
	check(not covered, "pickup bed is open")


func test_all_wheels_touch_the_ground() -> void:
	var d: VehicleData = load("res://data/vehicles/sedan.tres")
	var flat_seed := -1
	for sd in range(1, 400):
		if int(VehicleBuilder.variation_for(d, sd).flat) >= 0:
			flat_seed = sd
			break
	check(flat_seed > 0, "found a seed with a flat tyre")
	for sd in [5, flat_seed]:
		var mesh := VehicleBuilder.build_mesh(d, sd)
		var arr := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var ax := VehicleBuilder.axles(d)
		for z in [ax.x, ax.y]:
			for sx in [-1.0, 1.0]:
				var low := INF
				for i in verts.size():
					var v := verts[i]
					if _near_color(cols[i], VehicleBuilder.TYRE) and absf(v.z - z) < 0.5 and signf(v.x) == sx:
						low = minf(low, v.y)
				check_near(low, 0.0, 0.01, "seed %d wheel (%.1f, %.1f) touches the ground" % [sd, sx, z])
	var flat := VehicleBuilder.variation_for(d, flat_seed)
	check(not flat.has("tilt"), "no rigid tilt (only the flat corner sags)")


func _near_color(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01
