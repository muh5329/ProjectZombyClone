extends Node
## World time (autoload: TimeManager, Round 7).
##
## - [minutes]: game minutes since the world's start instant (float).
##   Calendar maths are GameClock statics; tuning is data/world/time_config.tres
##   (default 1 real second = 1 game minute → a day lasts 24 real minutes;
##   the world starts on 1 July, 07:00).
## - Time advances in _physics_process by the (Engine.time_scale-scaled)
##   physics delta, so every simulation that listens to it (needs,
##   spoilage) follows the speed controls. EventBus.time_advanced(from, to)
##   fires every tick; minute_passed / hour_passed / day_passed fire once per
##   whole unit crossed (also for a big advance()).
## - Speed steps (F5 pause · F6 1× · F7 2× · F8 4×, `,` slower / `.` faster):
##   pause = SceneTree.paused (this node keeps processing input); 2×/4× =
##   Engine.time_scale (PZ-like: the whole simulation runs faster). Fast-
##   forward is refused while a zombie chases the player ("Can't
##   fast-forward: danger") and drops back to 1× the moment one starts to.
## - Sleep (RestComponent): begin_sleep() sets Engine.time_scale to
##   config.sleep_engine_time_scale (zombies keep simulating) and skips game
##   time on top so it runs at config.sleep_minutes_per_second.
## - to_dict / from_dict for the save (Round 10). reset() is called by the
##   map's WorldConfig so every loaded world starts at minute 0 / 1×.

const CONFIG_PATH := "res://data/world/time_config.tres"
const STEP_PAUSED := 0
const STEP_NORMAL := 1
## Input actions → speed step (the two relative ones are handled apart).
const STEP_ACTIONS := {&"time_pause": 0, &"time_speed_1": 1, &"time_speed_2": 2, &"time_speed_3": 3}
const REASON_DANGER := "Can't fast-forward: danger"

var config: TimeConfig
var minutes: float = 0.0
var speed_step: int = STEP_NORMAL
var sleeping: bool = false
## Bumped by reset() / from_dict(): a clock that was LOADED (or restarted)
## is not elapsed time — item ages stamped in another epoch re-stamp
## instead of ageing (ItemInstance.sync_age), whatever the load order.
var epoch: int = 0
var _last_minute: int = 0
var _last_hour: int = 0
var _last_day: int = 0
var _danger_accum: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	config = load(CONFIG_PATH) as TimeConfig
	if config == null:
		config = TimeConfig.new()
	_sync_marks()
	EventBus.character_died.connect(_on_character_died)


## The player died: no pause / fast-forward / sleep speed left behind.
func _on_character_died(c: Node, _source: Node) -> void:
	if c == null or c != GameManager.player:
		return
	if sleeping:
		end_sleep()
	if speed_step != STEP_NORMAL:
		set_speed(STEP_NORMAL)


# --- Queries -----------------------------------------------------------------

func now() -> float:
	return minutes


func start_minute_of_day() -> float:
	return config.start_minute_of_day()


func hour() -> int:
	return GameClock.hour_of(minutes, start_minute_of_day())


func minute() -> int:
	return GameClock.minute_of(minutes, start_minute_of_day())


func hour_float() -> float:
	return GameClock.hour_float(minutes, start_minute_of_day())


## Whole days since the start day (0 on day 1).
func day_index() -> int:
	return GameClock.days_elapsed(minutes, start_minute_of_day())


## {month, day}.
func date() -> Dictionary:
	return GameClock.date_after(config.start_month, config.start_day, day_index())


func month() -> int:
	return int(date().month)


func season() -> StringName:
	return GameClock.season_of(month())


func clock_text() -> String:
	return GameClock.format_time(hour(), minute())


func date_text() -> String:
	var d := date()
	return GameClock.format_date(int(d.month), int(d.day))


func temperature_f() -> float:
	return GameClock.c_to_f(GameClock.temperature_c(month(), hour_float()))


func is_paused() -> bool:
	return speed_step == STEP_PAUSED


## Engine.time_scale of the current step.
func speed_scale() -> float:
	return _step_scale(speed_step)


# --- Advancing ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	var rate := config.minutes_per_second
	if sleeping:
		rate = config.sleep_minutes_per_second / maxf(config.sleep_engine_time_scale, 0.01)
	advance(delta * rate)
	if speed_step > STEP_NORMAL and not sleeping:
		_danger_accum += delta
		if _danger_accum >= 0.25:
			_danger_accum = 0.0
			if Danger.is_chased(get_tree(), GameManager.player):
				set_speed(STEP_NORMAL)
				_notice("Danger! Time back to normal")


## Move time forward by [game_minutes] (tests / sleep skips call it
## directly). Emits time_advanced once and the whole-unit signals.
func advance(game_minutes: float) -> void:
	if game_minutes <= 0.0:
		return
	var from := minutes
	minutes += game_minutes
	EventBus.time_advanced.emit(from, minutes)
	var m := int(floor(minutes))
	while _last_minute < m:
		_last_minute += 1
		EventBus.minute_passed.emit(_last_minute)
		var abs_minute := float(_last_minute) + start_minute_of_day()
		var h := int(floor(abs_minute / 60.0))
		if h != _last_hour:
			_last_hour = h
			EventBus.hour_passed.emit(h % 24, int(floor(abs_minute / 1440.0)))
		var d := int(floor(abs_minute / 1440.0))
		if d != _last_day:
			_last_day = d
			EventBus.day_passed.emit(d)


## Jump to an absolute minute WITHOUT simulating the gap (world load,
## tests setting the hour): no time_advanced / minute signals, so needs do
## not change (spoilage is age-based and does see the jump).
func set_minutes(total: float) -> void:
	minutes = maxf(total, 0.0)
	_sync_marks()


## Jump the clock to [h]:[m] (forward only: an earlier hour means the
## next day). Not simulated (see set_minutes).
func set_time_of_day(h: int, m: int = 0) -> void:
	var target := float(h * 60 + m)
	var cur := GameClock.minute_of_day(minutes, start_minute_of_day())
	var delta := fposmod(target - cur, 1440.0)
	set_minutes(minutes + delta)


func _sync_marks() -> void:
	_last_minute = int(floor(minutes))
	var abs_minute := float(_last_minute) + (start_minute_of_day() if config else 0.0)
	_last_hour = int(floor(abs_minute / 60.0))
	_last_day = int(floor(abs_minute / 1440.0))


# --- Speed controls ---------------------------------------------------------------

func _step_scale(step: int) -> float:
	var steps := config.speed_steps
	if steps.is_empty():
		return 1.0
	return float(steps[clampi(step, 0, steps.size() - 1)])


func max_step() -> int:
	return maxi(config.speed_steps.size() - 1, STEP_NORMAL)


## Change the speed step. Returns {ok, reason?}. Fast-forward (> 1×) is
## refused while chased; nothing changes while sleeping.
func set_speed(step: int) -> Dictionary:
	step = clampi(step, STEP_PAUSED, max_step())
	if sleeping:
		return {"ok": false, "reason": "Sleeping"}
	if step > STEP_NORMAL and Danger.is_chased(get_tree(), GameManager.player):
		return {"ok": false, "reason": REASON_DANGER}
	var changed := step != speed_step
	speed_step = step
	get_tree().paused = step == STEP_PAUSED
	Engine.time_scale = maxf(_step_scale(step), 0.0) if step != STEP_PAUSED else 1.0
	_danger_accum = 0.0
	if changed:
		EventBus.time_speed_changed.emit(speed_step, _step_scale(step))
	return {"ok": true, "step": step}


## Player request (keys): refusals go to the HUD notice.
func request_speed(step: int) -> Dictionary:
	var r := set_speed(step)
	if not r.ok:
		_notice(String(r.reason))
	return r


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	for action: StringName in STEP_ACTIONS:
		if InputMap.has_action(action) and event.is_action_pressed(action, false, true):
			get_viewport().set_input_as_handled()
			request_speed(int(STEP_ACTIONS[action]))
			return
	if InputMap.has_action(&"time_slower") and event.is_action_pressed(&"time_slower", false, true):
		get_viewport().set_input_as_handled()
		request_speed(maxi(speed_step - 1, STEP_PAUSED))
	elif InputMap.has_action(&"time_faster") and event.is_action_pressed(&"time_faster", false, true):
		get_viewport().set_input_as_handled()
		request_speed(mini(speed_step + 1, max_step()))


func _notice(reason: String) -> void:
	EventBus.interaction_refused.emit(GameManager.player, null, reason)


# --- Sleep -----------------------------------------------------------------------------

func begin_sleep() -> void:
	if get_tree().paused:
		get_tree().paused = false
	speed_step = STEP_NORMAL
	sleeping = true
	Engine.time_scale = maxf(config.sleep_engine_time_scale, 0.01)
	EventBus.time_speed_changed.emit(speed_step, Engine.time_scale)


func end_sleep() -> void:
	if not sleeping:
		return
	sleeping = false
	Engine.time_scale = 1.0
	speed_step = STEP_NORMAL
	EventBus.time_speed_changed.emit(speed_step, 1.0)


# --- Lifecycle / save -----------------------------------------------------------------

## New world: minute 0, 1×, not sleeping, engine at normal speed.
func reset() -> void:
	epoch += 1
	minutes = 0.0
	sleeping = false
	speed_step = STEP_NORMAL
	Engine.time_scale = 1.0
	if is_inside_tree():
		get_tree().paused = false
	_danger_accum = 0.0
	_sync_marks()


func to_dict() -> Dictionary:
	return {"minutes": minutes, "speed_step": speed_step}


func from_dict(d: Dictionary) -> void:
	epoch += 1
	sleeping = false
	set_minutes(float(d.get("minutes", 0.0)))
	speed_step = STEP_NORMAL
	Engine.time_scale = 1.0
	var step := int(d.get("speed_step", STEP_NORMAL))
	# A saved pause / fast-forward resumes at that speed only when safe.
	if step != STEP_NORMAL:
		set_speed(step)
