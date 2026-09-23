class_name Outfit
extends Resource
## One set of clothes for the procedural humanoid (HumanoidBuilder): colours
## per garment plus style flags. Data lives in data/characters/outfits/*.tres;
## survivors and zombies draw from the same pool (zombies are former
## townspeople, Project Zomboid style) — [zombie_weight] is the spawn weight.
## Colours are sRGB albedo.

@export var id: StringName = &""
@export var display_name: String = ""
@export_group("Upper body")
@export var shirt_color: Color = Color(0.85, 0.85, 0.82)
@export var short_sleeves: bool = true
## A jacket / hoodie / uniform coat over the shirt (colours the torso and
## both sleeves to the wrist).
@export var has_jacket: bool = false
@export var jacket_color: Color = Color(0.25, 0.3, 0.4)
## Open jacket: a strip of the shirt shows down the front.
@export var jacket_open: bool = false
## Hood hanging on the back (hoodies).
@export var hood: bool = false
@export_group("Lower body")
@export var pants_color: Color = Color(0.2, 0.28, 0.45)
@export var shorts: bool = false
@export var shoes_color: Color = Color(0.15, 0.12, 0.1)
@export var has_belt: bool = false
@export var belt_color: Color = Color(0.12, 0.1, 0.08)
@export_group("Headwear")
## &"none", &"cap", &"police_cap", &"hard_hat", &"fire_helmet", &"beanie".
@export var hat: StringName = &"none"
@export var hat_color: Color = Color(0.2, 0.2, 0.25)
@export_group("Details")
## Reflective bands (firefighter turnout coat, hi-vis vest).
@export var stripes: bool = false
@export var stripe_color: Color = Color(0.9, 0.85, 0.3)
## Hi-vis vest over the shirt (construction).
@export var vest: bool = false
@export var vest_color: Color = Color(0.95, 0.55, 0.1)
## Badge / name tag / chest patch on the left breast.
@export var badge: bool = false
@export var badge_color: Color = Color(0.85, 0.75, 0.3)
@export_group("Spawning")
## Relative weight when a zombie picks a random outfit (0 = never).
@export var zombie_weight: float = 1.0


## Problems with this outfit (empty = valid).
func validate() -> Array[String]:
	var out: Array[String] = []
	if id == &"":
		out.append("outfit without id")
	if not hat in [&"none", &"cap", &"police_cap", &"hard_hat", &"fire_helmet", &"beanie"]:
		out.append("%s: unknown hat '%s'" % [id, hat])
	if zombie_weight < 0.0:
		out.append("%s: negative zombie_weight" % id)
	return out
