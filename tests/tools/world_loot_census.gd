extends SceneTree
## Dev / evidence tool (Round 11): builds maps/world.tscn for a seed and
## rolls every container once (deterministic, as searching would) —
## prints food / drink items and weapons per settlement kind, and whether
## every settlement has a hammer.
##   godot --headless --path . -s tests/tools/world_loot_census.gd -- [seed ...]

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var seeds: Array[int] = []
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			seeds.append(int(a))
	if seeds.is_empty():
		seeds = [1337, 7, 99]
	var sm = root.get_node("SaveManager")
	for s in seeds:
		var map: Node = sm.instantiate_new_game("res://maps/world.tscn", s)
		map.get_node("NavRegion").bake_on_ready = false
		map.get_node("Zombies").auto_spawn = false
		root.add_child(map)
		await process_frame
		var builder = map.get_node("Generated")
		var food := 0
		var drink := 0
		var weapons := {}
		var hammers := {}
		var per_kind := {}
		for id in builder.buildings:
			var hb = builder.buildings[id]
			var settle: String = builder.layout.building(String(id)).settlement
			var skind := String(builder.layout.settlement(settle).kind)
			if not hammers.has(settle):
				hammers[settle] = false
			for c in hb.containers:
				c.ensure_loot()
				for inst in c.inventory.items:
					var d: ItemData = inst.data
					var n: int = inst.stack
					match d.category:
						ItemData.Category.FOOD:
							food += n
							per_kind[skind + "_food"] = int(per_kind.get(skind + "_food", 0)) + n
						ItemData.Category.DRINK:
							drink += n
						ItemData.Category.WEAPON:
							weapons[String(d.id)] = int(weapons.get(String(d.id), 0)) + n
							per_kind[skind + "_weapons"] = int(per_kind.get(skind + "_weapons", 0)) + n
					if d.id == &"hammer":
						hammers[settle] = true
		var missing: Array = []
		for k in hammers:
			if not hammers[k]:
				missing.append(k)
		print("seed %d: food %d, drink %d, weapons %s, per kind %s, settlements without a hammer: %s" % [s, food, drink, weapons, per_kind, missing])
		map.queue_free()
		await process_frame
		await process_frame
	quit(0)
