extends SceneTree
## Dev / evidence tool (Round 11): layout variety over many seeds.
##   godot --headless --path . -s tests/tools/world_variety.gd -- [first] [count] [--size=768]
## Prints town centre spread, block shapes, orientation spread, hamlet /
## farm counts, spawn kinds and rural road curvature (length / chord).

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var first := 1
	var count := 100
	var size := 768.0
	var nums: Array[int] = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--size="):
			size = float(a.trim_prefix("--size="))
		elif a.is_valid_int():
			nums.append(int(a))
	if nums.size() > 0:
		first = nums[0]
	if nums.size() > 1:
		count = nums[1]
	var gen: GDScript = load("res://worldgen/world_generator.gd")
	var prm: WorldGenParams = gen.default_params().duplicate()
	prm.world_size = Vector2(size, size)
	var cx: Array[float] = []
	var cz: Array[float] = []
	var angles: Array[float] = []
	var blocks := {}
	var hamlets := {}
	var hamlet_kinds := {}
	var farms := {}
	var spawn := {}
	var lots: Array[float] = []
	var ratios: Array[float] = []
	var second_hw := 0
	var loops := 0
	for s in range(first, first + count):
		var l: WorldLayout = gen.generate_fresh(s, prm)
		var town := l.settlement("town")
		cx.append((town.center as Vector2).x / size)
		cz.append((town.center as Vector2).y / size)
		angles.append(fposmod(float(town.get("angle_deg", 0.0)), 180.0))
		var bd := String(l.stats.get("town_blocks", "?"))
		blocks[bd] = int(blocks.get(bd, 0)) + 1
		var nh := 0
		var nf := 0
		for st in l.settlements:
			if st.kind == &"hamlet":
				nh += 1
				var hk := String(st.get("layout", "?"))
				hamlet_kinds[hk] = int(hamlet_kinds.get(hk, 0)) + 1
			elif st.kind == &"farmstead":
				nf += 1
		hamlets[nh] = int(hamlets.get(nh, 0)) + 1
		farms[nf] = int(farms.get(nf, 0)) + 1
		var sk := String(l.stats.get("spawn_settlement", "?")).rstrip("0123456789")
		spawn[sk] = int(spawn.get(sk, 0)) + 1
		var tl := 0
		for lt in l.lots:
			if lt.settlement == "town":
				tl += 1
		lots.append(tl)
		for rd in l.roads:
			var id := String(rd.id)
			if id == "hw_2":
				second_hw += 1
			if id.begins_with("loop"):
				loops += 1
			if not (rd.kind in [&"highway", &"county"]) or id.begins_with("hamlet"):
				continue
			var pts: PackedVector2Array = rd.points
			var length := 0.0
			for i in range(pts.size() - 1):
				length += pts[i].distance_to(pts[i + 1])
			var chord := pts[0].distance_to(pts[pts.size() - 1])
			if chord > 150.0:
				ratios.append(length / chord)
	print("seeds %d..%d at %d m" % [first, first + count - 1, int(size)])
	print("town centre x/size: min %.2f max %.2f sd %.2f ; z/size: min %.2f max %.2f sd %.2f" % [
		cx.min(), cx.max(), _sd(cx), cz.min(), cz.max(), _sd(cz)])
	var bins := [0, 0, 0, 0, 0, 0]
	for a in angles:
		bins[mini(int(a / 30.0), 5)] += 1
	print("town orientation (0-180 deg, 30 deg bins): ", bins)
	print("town blocks (cols x rows - dropped): ", blocks)
	print("town lots: min %d max %d mean %.1f" % [lots.min(), lots.max(), _mean(lots)])
	print("hamlets per world: ", hamlets, "  kinds: ", hamlet_kinds)
	print("farms per world: ", farms)
	print("spawn settlement kinds: ", spawn)
	print("second highway: %d, loop road: %d" % [second_hw, loops])
	ratios.sort()
	print("rural road length/chord: n %d mean %.3f median %.3f p10 %.3f p90 %.3f" % [ratios.size(), _mean(ratios),
		ratios[ratios.size() / 2], ratios[int(ratios.size() * 0.1)], ratios[int(ratios.size() * 0.9)]])
	quit(0)


func _mean(a: Array) -> float:
	var t := 0.0
	for v in a:
		t += float(v)
	return t / maxf(a.size(), 1.0)


func _sd(a: Array) -> float:
	var m := _mean(a)
	var t := 0.0
	for v in a:
		t += (float(v) - m) * (float(v) - m)
	return sqrt(t / maxf(a.size(), 1.0))
