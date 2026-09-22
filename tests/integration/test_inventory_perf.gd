extends "res://tests/test_case.gd"
## Round 6 critic: the inventory screen must stay cheap with hundreds of
## stacks. 200 + 200 rows: a refresh after one transfer < 15 ms (rows are
## diffed), Loot All of 199 stacks < 60 ms (one transaction: one
## `changed` per side, one encumbrance recompute, one UI refresh).

var scene: Node
var player: Player
var window: LootWindow
var c: LootContainer

const IDS: Array[StringName] = [&"hammer", &"kitchen_knife", &"crowbar", &"screwdriver", &"wrench", &"saw", &"tin_opener", &"pipe"]


func setup() -> void:
	scene = await spawn_scene("res://maps/test_ground.tscn")
	scene.get_node("Zombies").auto_spawn = false
	player = scene.get_node("Player")
	player.get_node("Controller").scripted = true
	player.get_node("Combat").scripted = true
	player.get_node("Interaction").scripted = true
	window = scene.get_node("LootWindow")
	c = null
	for n in tree.get_nodes_in_group(LootContainer.GROUP):
		if n.persist_id == "HouseA/kitchen/0":
			c = n
	var front := c.global_basis.z
	front.y = 0.0
	player.global_position = c.global_position + front.normalized() * (c.size.z * 0.5 + 0.75) + Vector3.UP * 0.1
	await physics_frames(3)
	c.open(player)
	c.inventory.clear()
	c.inventory.capacity = -1.0
	player.inventory.capacity = -1.0
	await frames(2)


func teardown() -> void:
	await despawn(scene)


## [n] non-stackable stacks (condition items: one row each).
func _fill(inv: ItemContainer, n: int) -> void:
	inv.begin_batch()
	for i in n:
		inv.add_id(IDS[i % IDS.size()], 1)
	inv.end_batch()


func test_refresh_with_400_rows_is_diffed_and_fast() -> void:
	_fill(c.inventory, 200)
	_fill(player.inventory, 200)
	window.refresh()  # cold: builds the row pool
	await frames(2)
	check_eq(window.visible_row_count(LootWindow.SIDE_CONTAINER), 200, "200 container rows")
	check_eq(window.visible_row_count(LootWindow.SIDE_PLAYER), 200, "200 player rows")
	var t0 := Time.get_ticks_usec()
	window.refresh()
	var warm := (Time.get_ticks_usec() - t0) / 1000.0
	check_lt(float(window.player_panel.last_rebound + window.container_panel.last_rebound), 1.0, "nothing changed → nothing rebound")
	# One transfer, then a refresh: only the touched rows rebind.
	var it := c.inventory.items[100]
	check(window.transfer_item(LootWindow.SIDE_CONTAINER, it).ok, "one transfer")
	t0 = Time.get_ticks_usec()
	window.refresh()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("PERF inventory refresh: unchanged %.2f ms, after one transfer %.2f ms (rebound %d + %d rows)" % [warm, ms, window.player_panel.last_rebound, window.container_panel.last_rebound])
	check_lt(ms, 15.0, "refresh with 400 rows after one transfer < 15 ms (%.2f)" % ms)
	check_lt(float(window.container_panel.last_rebound), 110.0, "container side: only the rows after the gap moved (%d)" % window.container_panel.last_rebound)


func test_loot_all_of_199_items_is_one_transaction() -> void:
	_fill(c.inventory, 199)
	window.refresh()
	await frames(2)
	var changes := [0, 0]
	player.inventory.changed.connect(func(): changes[0] += 1)
	c.inventory.changed.connect(func(): changes[1] += 1)
	var enc: Encumbrance = player.encumbrance
	var e0 := enc.emit_count
	var t0 := Time.get_ticks_usec()
	var r := window.loot_all()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("PERF loot_all 199 stacks: %.2f ms" % ms)
	check(r.ok and r.moved == 199 and c.inventory.is_empty(), "everything looted (%s)" % str(r))
	check_lt(ms, 60.0, "Loot All of 199 stacks < 60 ms (%.2f)" % ms)
	check(changes[0] == 1 and changes[1] == 1, "one changed per side (%s)" % str(changes))
	await frames(2)
	check_eq(enc.emit_count - e0, 1, "one encumbrance update")
	var t1 := Time.get_ticks_usec()
	window.refresh()
	var rms := (Time.get_ticks_usec() - t1) / 1000.0
	print("PERF refresh after loot_all: %.2f ms" % rms)
	check_eq(window.visible_row_count(LootWindow.SIDE_PLAYER), 199, "rows follow")
