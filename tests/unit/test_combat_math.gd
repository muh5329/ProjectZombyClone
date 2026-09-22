extends "res://tests/test_case.gd"
## Pure melee maths: arc target selection, charge curve, stamina damage
## multiplier, weapon data (distinct feel), item condition.

const BAT := preload("res://data/items/weapons/baseball_bat.tres")
const KNIFE := preload("res://data/items/weapons/kitchen_knife.tres")
const CROWBAR := preload("res://data/items/weapons/crowbar.tres")
const HAMMER := preload("res://data/items/weapons/hammer.tres")
const PIPE := preload("res://data/items/weapons/pipe.tres")
const FISTS := preload("res://data/items/weapons/fists.tres")
const SHOVE := preload("res://data/items/weapons/shove.tres")


func test_arc_selection_reach_and_angle() -> void:
	var o := Vector3.ZERO
	var fwd := Vector3.FORWARD  # -Z
	var pts := [
		Vector3(0, 0, -1.0),    # 0 straight ahead, in reach
		Vector3(0, 0, -2.0),    # 1 too far
		Vector3(0, 0, 1.0),     # 2 behind
		Vector3(1.0, 0, -1.0),  # 3 45° right, 1.41 m
		Vector3(-0.9, 0, -0.5), # 4 ~61° left, 1.03 m
	]
	var r := HitResolver.select_targets(o, fwd, 1.4, deg_to_rad(120), 5, pts)
	check(r.has(0), "ahead is hit")
	check(not r.has(1), "beyond reach is not")
	check(not r.has(2), "behind is not")
	check(not r.has(3), "1.41 m > 1.4 reach (no radius)")
	check(not r.has(4), "61° outside a ±60° arc")
	r = HitResolver.select_targets(o, fwd, 1.4, deg_to_rad(120), 5, pts, 0.3)
	check(r.has(3), "target radius widens the reach")
	check(r.has(4), "…and the arc")
	check_eq(r[0], 0, "closest first")
	# Narrow knife arc (40° = ±20°).
	r = HitResolver.select_targets(o, fwd, 0.9, deg_to_rad(40), 5, [Vector3(0.2, 0, -0.8), Vector3(0.5, 0, -0.7)])
	check_eq(r, [0] as Array[int], "only the target within ±20°")


func test_arc_selection_caps_and_degenerate() -> void:
	var pts := [Vector3(0, 0, -1.2), Vector3(0.2, 0, -0.6), Vector3(-0.3, 0, -0.9), Vector3(0, 0, -1.0)]
	var r := HitResolver.select_targets(Vector3.ZERO, Vector3.FORWARD, 1.4, deg_to_rad(120), 3, pts)
	check_eq(r.size(), 3, "capped at max_targets")
	check_eq(r[0], 1, "nearest first (0.63 m)")
	check(not r.has(0), "farthest dropped")
	check(HitResolver.select_targets(Vector3.ZERO, Vector3.ZERO, 1.4, PI, 3, pts).is_empty(), "no direction → nothing")
	check(HitResolver.select_targets(Vector3.ZERO, Vector3.FORWARD, 1.4, PI, 0, pts).is_empty(), "max 0 → nothing")
	check(HitResolver.select_targets(Vector3.ZERO, Vector3.FORWARD, 1.4, PI, 3, []).is_empty(), "no candidates")
	# Y is ignored; origin offsets respected.
	r = HitResolver.select_targets(Vector3(5, 0, 5), Vector3.RIGHT, 1.0, deg_to_rad(60), 1, [Vector3(5.8, 3.0, 5.1)])
	check_eq(r, [0] as Array[int], "flat distance, rotated direction")
	# A target on top of the attacker is always inside.
	check_eq(HitResolver.select_targets(Vector3.ZERO, Vector3.FORWARD, 1.0, deg_to_rad(10), 1, [Vector3(0, 0, 0.00001)]).size(), 1, "overlapping target")


func test_charge_curve() -> void:
	check_near(SwingStateMachine.charge_multiplier(0.0), 0.6, 0.0001, "tap = ×0.6")
	check_near(SwingStateMachine.charge_multiplier(0.5), 0.95, 0.0001, "half = ×0.95")
	check_near(SwingStateMachine.charge_multiplier(1.0), 1.3, 0.0001, "1 s = ×1.3")
	check_near(SwingStateMachine.charge_multiplier(5.0), 1.3, 0.0001, "capped")
	check_near(SwingStateMachine.charge_multiplier(-1.0), 0.6, 0.0001, "negative clamps")
	check_near(SwingStateMachine.charge_multiplier(0.3, 0.5, 1.5, 0.0), 1.5, 0.0001, "zero charge time → max")
	var prev := 0.0
	for i in 11:
		var m := SwingStateMachine.charge_multiplier(i * 0.1)
		check(m >= prev, "monotonic at %.1f" % (i * 0.1))
		prev = m


func test_stamina_damage_multiplier() -> void:
	check_eq(HitResolver.stamina_damage_multiplier(false, false), 1.0, "fresh")
	check_near(HitResolver.stamina_damage_multiplier(false, true), 0.85, 0.0001, "low stamina")
	check_near(HitResolver.stamina_damage_multiplier(true, true), 0.6, 0.0001, "exhausted wins")


func test_weapons_have_distinct_feel() -> void:
	for w in [BAT, KNIFE, CROWBAR, HAMMER, PIPE, FISTS, SHOVE]:
		check(w is WeaponData and w is ItemData, "%s is WeaponData/ItemData" % w.id)
		check(w.damage_max >= w.damage_min, "%s damage range" % w.id)
		check(w.windup_time() + w.active_time() <= w.swing_time + 0.0001, "%s timing fits" % w.id)
	check_eq(BAT.reach, 1.4, "bat reach")
	check_eq(BAT.arc_degrees, 120.0, "bat arc")
	check_eq(BAT.max_targets, 2, "bat targets")
	check_near(BAT.swing_time, 1.1, 0.001, "bat swing")
	check_near(BAT.knockdown_chance, 0.15, 0.001, "bat knockdown")
	check_near(BAT.knockback, 0.3, 0.001, "bat knockback")
	check_eq(BAT.stamina_cost, 12.0, "bat stamina")
	check(not KNIFE.can_stagger and BAT.can_stagger, "knife never staggers")
	check_eq(KNIFE.reach, 0.9, "knife reach")
	check_eq(KNIFE.arc_degrees, 40.0, "knife arc")
	check_eq(KNIFE.max_targets, 1, "knife 1 target")
	check_near(KNIFE.swing_time, 0.4, 0.001, "knife fast")
	check_eq(KNIFE.stamina_cost, 3.0, "knife stamina")
	check_gt(KNIFE.crit_chance, BAT.crit_chance * 2.0, "knife crits much more")
	check_lt(KNIFE.damage_max, BAT.damage_min, "knife hits softer")
	check_gt(float(CROWBAR.max_condition), float(BAT.max_condition) * 2.0, "crowbar durable")
	check_near(CROWBAR.swing_time, 0.75, 0.001, "crowbar swing")
	check_lt(HAMMER.reach, CROWBAR.reach, "hammer short")
	check_lt(HAMMER.swing_time, CROWBAR.swing_time, "hammer fast")
	check(PIPE.reach > HAMMER.reach and PIPE.reach < BAT.reach, "pipe medium reach")
	check_eq(FISTS.reach, 0.8, "fists reach")
	check_eq(FISTS.arc_degrees, 60.0, "fists arc")
	check(FISTS.damage_min == 3.0 and FISTS.damage_max == 5.0, "fists 3-5")
	check_near(FISTS.swing_time, 0.5, 0.001, "fists 0.5 s")
	check_eq(FISTS.max_condition, 0, "fists never break")
	check(SHOVE.is_shove, "shove flag")
	check(SHOVE.reach == 1.0 and SHOVE.arc_degrees == 90.0 and SHOVE.max_targets == 3, "shove 1 m / 90° / 3")
	check_near(SHOVE.knockback, 1.2, 0.001, "shove knockback")
	check_near(SHOVE.knockdown_chance_against(false), 0.25, 0.001, "shove 25 %")
	check_near(SHOVE.knockdown_chance_against(true), 0.5, 0.001, "shove 50 % vs windup")
	check_near(BAT.knockdown_chance_against(true), 0.15, 0.001, "no windup override → same")
	check_eq(SHOVE.stamina_cost, 5.0, "shove stamina")


func test_item_instance_condition_and_break() -> void:
	var it := ItemInstance.new(BAT)
	check_eq(it.condition, BAT.max_condition, "starts at max condition")
	check(it.is_weapon(), "weapon")
	var broke := []
	it.broken.connect(func(): broke.append(true))
	check(not it.wear(0), "0 wear no-op")
	it.wear(BAT.max_condition - 1)
	check_eq(it.condition, 1, "worn")
	check_near(it.condition_fraction(), 1.0 / BAT.max_condition, 0.0001, "fraction")
	check(it.wear(5), "breaks")
	check_eq(it.condition, 0, "clamped at 0")
	check(it.is_broken(), "broken")
	check_eq(broke.size(), 1, "broken emitted once")
	check(not it.wear(1), "no further wear")
	var f := ItemInstance.new(FISTS)
	check(not f.wear(3) and not f.is_broken(), "no-condition items never break")
	var d := it.to_dict()
	var back := ItemInstance.from_dict(d)
	check(back.data == BAT and back.condition == 0, "dict round trip")
	var partial := ItemInstance.new(BAT, 5)
	check_eq(partial.condition, 5, "explicit condition")


func test_swing_state_machine_phases_and_queue() -> void:
	var sm := SwingStateMachine.new()
	check_eq(sm.press(), &"charge", "idle press charges")
	sm.tick(0.5)
	check_near(sm.charge_time, 0.5, 0.0001, "charge time")
	check(sm.release(), "release swings")
	sm.begin(FISTS, null, 1.0, Vector3.FORWARD)
	check_eq(sm.phase, SwingStateMachine.Phase.WINDUP, "windup")
	check_eq(sm.press(), &"queued", "press mid-swing queues")
	check(not sm.release(), "queued release does not swing now")
	check(sm.queued and not sm.queued_held, "queued, released")
	var events: Array[StringName] = []
	for i in 60:
		var e := sm.tick(1.0 / 60.0)
		if e != &"":
			events.append(e)
		if e == &"done":
			break
	check_eq(events, [&"active", &"recovery", &"done"] as Array[StringName], "phase events")
	var q := sm.finish()
	check(q.queued and not q.held and not q.shove, "snapshot has the queued swing")
	check(not sm.queued and not sm.queued_held and not sm.queued_shove, "finish clears the queue")
	# Interrupted swing: finish() mid-windup also drops the queue.
	sm.begin(FISTS, null, 1.0, Vector3.FORWARD)
	sm.queue_shove()
	sm.finish()
	check(not sm.queued and not sm.queued_shove, "interrupt clears queued shove")
	check_eq(sm.phase, SwingStateMachine.Phase.IDLE, "idle")
	# Pain scales the phases.
	sm.begin(FISTS, null, 1.0, Vector3.FORWARD, 1.3)
	check_near(sm.phase_left, FISTS.windup_time() * 1.3, 0.0001, "time scale")
