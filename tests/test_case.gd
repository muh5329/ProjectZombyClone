extends RefCounted
## Tiny test base. Test scripts extend this and define `test_*` methods.
## Methods may be coroutines (use `await`). Runner: tests/test_runner.gd.

var tree: SceneTree
var _failures: Array[String] = []
var _checks: int = 0


func setup() -> void:
	pass


func teardown() -> void:
	pass


func fail(msg: String) -> void:
	_failures.append(msg)


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		fail(msg)


func check_eq(a: Variant, b: Variant, msg: String = "") -> void:
	_checks += 1
	if a != b:
		fail("%s expected %s got %s" % [msg, str(b), str(a)])


func check_near(a: float, b: float, tol: float, msg: String = "") -> void:
	_checks += 1
	if absf(a - b) > tol:
		fail("%s expected %.4f ± %.4f got %.4f" % [msg, b, tol, a])


func check_gt(a: float, b: float, msg: String = "") -> void:
	_checks += 1
	if not (a > b):
		fail("%s expected > %.4f got %.4f" % [msg, b, a])


func check_lt(a: float, b: float, msg: String = "") -> void:
	_checks += 1
	if not (a < b):
		fail("%s expected < %.4f got %.4f" % [msg, b, a])


## Advance N physics frames.
func physics_frames(n: int) -> void:
	for i in n:
		await tree.physics_frame


## Advance N idle frames.
func frames(n: int) -> void:
	for i in n:
		await tree.process_frame


## Advance idle frames until [pred] returns true or [max_frames] elapse.
## Returns true if the predicate was satisfied. Use this instead of fixed
## frame counts for anything that interpolates with wall-clock delta.
func wait_until(pred: Callable, max_frames: int = 600) -> bool:
	for i in max_frames:
		if pred.call():
			return true
		await tree.process_frame
	return pred.call()


## Advance PHYSICS frames until [pred] is true or [max_frames] elapse.
## Use this for gameplay timers (AI, cooldowns): headless process frames
## can run much faster than the 60 Hz physics tick.
func wait_physics_until(pred: Callable, max_frames: int = 600) -> bool:
	for i in max_frames:
		if pred.call():
			return true
		await tree.physics_frame
	return pred.call()


## Instantiate a scene under the root and wait a frame so _ready has run.
func spawn_scene(path: String) -> Node:
	var scene: PackedScene = load(path)
	var inst := scene.instantiate()
	tree.root.add_child(inst)
	await tree.process_frame
	return inst


func despawn(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()
		await tree.process_frame
