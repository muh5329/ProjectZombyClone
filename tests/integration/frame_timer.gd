extends Node
## Round 12 test / perf helper: records the wall time of every main-loop
## iteration (the interval between consecutive _process calls, taken at
## the very start of each frame — process_priority is the lowest), so a
## frame's physics steps, script work, node deletions and navigation sync
## are all inside one interval. Headless there is no vsync: an interval is
## the frame's own cost.

var intervals: Array[float] = []
var recording: bool = false
## Optional: called every frame, its return value stored in [notes]
## (what the systems did that frame — slow-frame diagnostics).
var probe: Callable = Callable()
var notes: Array = []
var _last: int = 0


func _ready() -> void:
	process_priority = -100000
	process_physics_priority = -100000


func start() -> void:
	intervals.clear()
	notes.clear()
	_last = Time.get_ticks_usec()
	recording = true


func stop() -> void:
	recording = false


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if recording:
		intervals.append((now - _last) / 1000.0)
		notes.append(probe.call() if probe.is_valid() else null)
	_last = now


## "<ms> ms: <note of that frame> / <note of the frame before>" for every
## frame over [limit] ms.
func slow_report(limit: float, max_n: int = 6) -> Array:
	var out: Array = []
	for i in intervals.size():
		if intervals[i] > limit and out.size() < max_n:
			out.append("%.1f ms: %s / prev %s" % [intervals[i], str(notes[i]), str(notes[i - 1] if i > 0 else null)])
	return out


func worst() -> float:
	var w := 0.0
	for v in intervals:
		w = maxf(w, v)
	return w


func average() -> float:
	var t := 0.0
	for v in intervals:
		t += v
	return t / maxf(intervals.size(), 1.0)


func percentile(p: float) -> float:
	if intervals.is_empty():
		return 0.0
	var s := intervals.duplicate()
	s.sort()
	return s[mini(int(s.size() * p), s.size() - 1)]
