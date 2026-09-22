class_name SwingStateMachine
extends RefCounted
## The timing half of a melee fighter: charge, swing phases and the
## one-deep input queue. Pure (no scene tree, no stamina, no physics):
## MeleeCombat feeds it input and delta and reacts to what tick() returns.
##
## Phases: IDLE → CHARGING (press) → WINDUP (begin) → ACTIVE → RECOVERY →
## (tick returns &"done"; the owner calls finish()) → IDLE.
## Pressing / shoving during a swing queues ONE follow-up. finish()
## returns the queue snapshot and ALWAYS clears it, so an interrupted
## swing (busy, death) can never leave a stale queued swing behind.

enum Phase { IDLE, CHARGING, WINDUP, ACTIVE, RECOVERY }

var phase: Phase = Phase.IDLE
## Seconds the attack button has been held (charging or queued-held).
var charge_time: float = 0.0
## Swing in progress.
var weapon: WeaponData = null
var item: ItemInstance = null
var charge: float = 1.0
var direction: Vector3 = Vector3.FORWARD
## Swing time multiplier of this swing (pain).
var time_scale: float = 1.0
var phase_left: float = 0.0

var queued: bool = false
var queued_held: bool = false
var queued_shove: bool = false


## ×min at a tap, rising linearly to ×max after [seconds] of holding.
static func charge_multiplier(held: float, p_min: float = 0.6, p_max: float = 1.3, seconds: float = 1.0) -> float:
	if seconds <= 0.0:
		return p_max
	return lerpf(p_min, p_max, clampf(held / seconds, 0.0, 1.0))


func is_swinging() -> bool:
	return phase == Phase.WINDUP or phase == Phase.ACTIVE or phase == Phase.RECOVERY


## Attack pressed. Returns &"charge" (started charging), &"queued" (a
## swing is in progress) or &"" (nothing).
func press() -> StringName:
	if phase == Phase.IDLE:
		phase = Phase.CHARGING
		charge_time = 0.0
		return &"charge"
	if is_swinging():
		queued = true
		queued_held = true
		queued_shove = false
		charge_time = 0.0
		return &"queued"
	return &""


## Attack released. True when a charge should turn into a swing now (the
## owner begins it with charge_time); a queued press is marked released.
func release() -> bool:
	if phase == Phase.CHARGING:
		phase = Phase.IDLE
		return true
	if queued and queued_held:
		queued_held = false
	return false


func queue_shove() -> void:
	queued = true
	queued_shove = true
	queued_held = false


func cancel_charge() -> void:
	if phase == Phase.CHARGING:
		phase = Phase.IDLE
	clear_queue()


func clear_queue() -> void:
	queued = false
	queued_held = false
	queued_shove = false


## Keep charging after a queued, still-held press ([held] seconds so far).
func resume_charge(held: float) -> void:
	phase = Phase.CHARGING
	charge_time = held


func begin(w: WeaponData, p_item: ItemInstance, p_charge: float, p_direction: Vector3, p_time_scale: float = 1.0) -> void:
	weapon = w
	item = p_item
	charge = p_charge
	direction = p_direction
	time_scale = maxf(p_time_scale, 0.01)
	phase = Phase.WINDUP
	phase_left = w.windup_time() * time_scale


## Advance by [delta]. Returns &"active" (entered the active window),
## &"recovery", &"done" (recovery over: call finish()) or &"".
func tick(delta: float) -> StringName:
	if queued and queued_held:
		charge_time += delta
	match phase:
		Phase.CHARGING:
			charge_time += delta
		Phase.WINDUP:
			phase_left -= delta
			if phase_left <= 0.0:
				phase = Phase.ACTIVE
				phase_left = weapon.active_time() * time_scale
				return &"active"
		Phase.ACTIVE:
			phase_left -= delta
			if phase_left <= 0.0:
				phase = Phase.RECOVERY
				phase_left = weapon.recovery_time() * time_scale
				return &"recovery"
		Phase.RECOVERY:
			phase_left -= delta
			if phase_left <= 0.0:
				return &"done"
	return &""


## End the swing (normally or interrupted). Returns the queue snapshot
## {queued, held, shove, charge_time} and clears the queue.
func finish() -> Dictionary:
	var q := {"queued": queued, "held": queued_held, "shove": queued_shove, "charge_time": charge_time}
	phase = Phase.IDLE
	phase_left = 0.0
	clear_queue()
	return q
