class_name SoundMath
extends RefCounted
## Pure sound-propagation maths (unit-tested; no scene access).
##
## Attenuation: every obstacle between the sound and the ear multiplies
## the radius — wall ×0.5, closed door ×0.6, closed window ×0.7, other
## solid props ×0.85, anything open ×1.0 — and the product never drops
## below MIN_ATTENUATION (0.15: a scream next door is still faintly heard).
## A listener hears when its "slack" (effective radius − path length) is
## ≥ 0; the perceived strength is intensity × slack / full radius.

const WALL := &"wall"
const DOOR_CLOSED := &"door_closed"
const WINDOW_CLOSED := &"window_closed"
const OPEN := &"open"
const PROP := &"prop"

const FACTORS := {
	WALL: 0.5,
	DOOR_CLOSED: 0.6,
	WINDOW_CLOSED: 0.7,
	PROP: 0.85,
	OPEN: 1.0,
}
const MIN_ATTENUATION := 0.15


static func obstacle_factor(kind: StringName) -> float:
	return float(FACTORS.get(kind, FACTORS[WALL]))


## Radius multiplier for the obstacles [kinds] (1.0 when none).
static func attenuation(kinds: Array) -> float:
	if kinds.is_empty():
		return 1.0
	var a := 1.0
	for k in kinds:
		a *= obstacle_factor(StringName(k))
	return maxf(a, MIN_ATTENUATION)


## The radius a listener effectively hears at.
static func effective_radius(radius: float, atten: float, sensitivity: float = 1.0, masking: float = 1.0) -> float:
	return maxf(radius, 0.0) * atten * maxf(sensitivity, 0.0) * maxf(masking, 0.0)


## effective radius − path length (≥ 0 → audible).
static func slack(eff_radius: float, path_length: float) -> float:
	return eff_radius - path_length


## Slack of the path through an opening: the sound reaches the opening
## [d_to_opening] away with [atten_to_opening] and then spreads from it
## unobstructed for [d_from_opening].
static func via_opening_slack(radius: float, atten_to_opening: float, d_to_opening: float,
		d_from_opening: float, sensitivity: float = 1.0, masking: float = 1.0) -> float:
	return effective_radius(radius, atten_to_opening, sensitivity, masking) - d_to_opening - d_from_opening


## How loud the sound is at the listener, 0..1: [intensity] scaled by how
## much of the full radius ([full_radius] = radius × sensitivity ×
## masking) is left over after the attenuated path.
static func perceived(intensity: float, slack_m: float, full_radius: float) -> float:
	if slack_m < 0.0:
		return 0.0
	return clampf(intensity * slack_m / maxf(full_radius, 0.01), 0.0, 1.0)


## Priority: a zombie already following a sound switches only to one that
## is at least as strong as the current one after it faded by
## [decay_per_second] × [age_seconds].
static func should_retarget(current_strength: float, age_seconds: float, new_strength: float,
		decay_per_second: float = 0.05) -> bool:
	return new_strength >= current_strength - maxf(age_seconds, 0.0) * decay_per_second


## True when [point] lies on the outward side of an opening at [center]
## with outward normal [outward] (sound leaking out radiates into that
## half-space only).
static func on_outward_side(center: Vector3, outward: Vector3, point: Vector3) -> bool:
	var d := point - center
	d.y = 0.0
	return d.dot(Vector3(outward.x, 0.0, outward.z)) > 0.0
