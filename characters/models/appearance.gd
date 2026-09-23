class_name Appearance
extends RefCounted
## What one procedural person looks like: an Outfit plus body colours and
## hair, and (zombies) decay: grey skin, blood and torn sleeves. Pure data
## for HumanoidBuilder; [key] identifies identical looks so meshes are
## shared (CharacterAssets caches one ArrayMesh per key).

const HAIR_STYLES: Array[StringName] = [&"short", &"long", &"buzz", &"ponytail", &"bald"]
const SKIN_TONES: Array[Color] = [
	Color(0.84, 0.6, 0.46), Color(0.76, 0.52, 0.37), Color(0.64, 0.43, 0.3),
	Color(0.48, 0.31, 0.2), Color(0.34, 0.22, 0.14), Color(0.8, 0.56, 0.41),
]
const HAIR_COLORS: Array[Color] = [
	Color(0.07, 0.06, 0.05), Color(0.2, 0.13, 0.08), Color(0.36, 0.23, 0.13),
	Color(0.72, 0.58, 0.34), Color(0.58, 0.57, 0.55), Color(0.48, 0.2, 0.09),
]
## Grey-green / grey-blue / pale / dark rot tones mixed into a zombie's skin.
const ROT_TONES: Array[Color] = [
	Color(0.45, 0.5, 0.4), Color(0.42, 0.47, 0.41), Color(0.48, 0.52, 0.42), Color(0.4, 0.45, 0.37),
]

var outfit: Outfit
var skin: Color = SKIN_TONES[0]
var hair_color: Color = HAIR_COLORS[1]
var hair_style: StringName = &"short"
var zombie: bool = false
## 0..1 how much blood is smeared on the clothes (zombies).
var blood: float = 0.0
## Torn sleeves per arm (left, right): the forearm cloth is gone.
var torn_left: bool = false
var torn_right: bool = false
## Seed of the blood / dirt pattern.
var pattern_seed: int = 0
## Uniform body scale (height variation, applied on the model node).
var height_scale: float = 1.0


## Deterministic random look for [seed_value] from [outfits] (weighted by
## zombie_weight for zombies, uniform otherwise).
static func random(seed_value: int, outfits: Array, as_zombie: bool) -> Appearance:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var a := Appearance.new()
	a.outfit = pick_outfit(outfits, rng, as_zombie)
	var tone: Color = SKIN_TONES[rng.randi() % SKIN_TONES.size()]
	a.hair_color = HAIR_COLORS[rng.randi() % HAIR_COLORS.size()]
	a.hair_style = HAIR_STYLES[rng.randi() % HAIR_STYLES.size()]
	a.height_scale = rng.randf_range(0.94, 1.05)
	a.pattern_seed = rng.randi() % 997
	a.zombie = as_zombie
	if as_zombie:
		var rot: Color = ROT_TONES[rng.randi() % ROT_TONES.size()]
		a.skin = zombie_skin(tone, rot)
		a.hair_color = a.hair_color.lerp(Color(0.3, 0.3, 0.28), 0.3)
		a.blood = rng.randf_range(0.35, 1.0)
		a.torn_left = rng.randf() < 0.45
		a.torn_right = rng.randf() < 0.45
	else:
		a.skin = tone
	return a


## Pure: rotting flesh — a flat grey-green rot tone, only a hint of the
## living tone's darkness (no lerp back toward living colours).
static func zombie_skin(tone: Color, rot: Color) -> Color:
	return rot.darkened(clampf((0.6 - tone.v) * 0.3, 0.0, 0.12))


static func pick_outfit(outfits: Array, rng: RandomNumberGenerator, weighted: bool) -> Outfit:
	if outfits.is_empty():
		rng.randf()
		return Outfit.new()
	var total := 0.0
	for o: Outfit in outfits:
		total += o.zombie_weight if weighted else 1.0
	var r := rng.randf() * total
	for o: Outfit in outfits:
		r -= o.zombie_weight if weighted else 1.0
		if r <= 0.0:
			return o
	return outfits[outfits.size() - 1]


## Identical keys build identical meshes.
func key() -> String:
	return "%s|%s|%s|%s|%d|%.2f|%d%d|%d" % [outfit.id if outfit else &"", skin.to_html(false),
		hair_color.to_html(false), hair_style, int(zombie), blood, int(torn_left), int(torn_right), pattern_seed]
