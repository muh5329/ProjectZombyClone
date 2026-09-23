class_name SoundCategory
extends Resource
## One kind of gameplay sound (data: data/audio/sound_categories.tres).
## A SoundEvent copies these defaults; emitters may override radius /
## intensity per event (a weapon's own noise radius, encumbrance…).

## Id used by emitters: &"footstep_jog", &"window_smash"…
@export var id: StringName = &""
## Base audible radius in metres (before attenuation and hearing).
@export var radius: float = 5.0
## Loudness 0..1 (how urgently listeners react; see SoundMath.perceived).
@export_range(0.0, 1.0) var intensity: float = 0.5
## Seconds the event stays "alive" (debug rings, late queries).
@export var duration: float = 1.0
## Free text for designers.
@export var note: String = ""
