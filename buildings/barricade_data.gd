class_name BarricadeData
extends Resource
## One kind of barricade (data/barricades/*.tres). Round 9 ships wooden
## planks nailed across a window or a door; metal sheets and furniture
## share the same numbers later. Everything the barricade rules need lives
## here — BarricadeComponent / the zombie AI read it, never hard-code it.
##
## Pure helpers (unit-tested): missing_reason(), can_add(), remove_yield(),
## build_seconds_for(), plank_health_for(), sound_factor(), vision_blocked().

const MATERIAL_WOOD := &"wood_plank"
const MATERIAL_METAL := &"metal_sheet"
const MATERIAL_FURNITURE := &"furniture"

@export var id: StringName = &"wood_planks"
@export var display_name: String = "Wooden planks"
## wood_plank / metal_sheet (later) / furniture.
@export var material: StringName = MATERIAL_WOOD

@export_group("Planks")
## Hit points of one freshly nailed plank (before the carpentry bonus).
@export var plank_health: float = 60.0
@export var max_planks_window: int = 4
@export var max_planks_door: int = 4
## Colour of a healthy plank; damaged planks darken toward [damaged_color].
@export var plank_color: Color = Color(0.56, 0.39, 0.22)
@export var damaged_color: Color = Color(0.27, 0.2, 0.14)

@export_group("Building")
## Tool tags that can nail a plank (any one of them).
@export var build_tool_tags: Array[StringName] = [&"hammer"]
## Item consumed per plank ([material_item]) and nails per plank.
@export var material_item: StringName = &"plank"
@export var material_per_plank: int = 1
@export var nails_item: StringName = &"nails"
@export var nails_per_plank: int = 2
## Seconds to nail one plank at carpentry 0.
@export var build_seconds: float = 3.0
## SoundManager category made while nailing (18 m — PZ hammering is loud).
@export var build_noise: StringName = &"hammering"
## Carpentry XP per nailed plank.
@export var xp_per_plank: float = 10.0

@export_group("Removing")
## tool tag → {seconds, plank_chance, nails_chance}: what "Remove
## barricade" costs and gives back per plank (the first matching tag wins,
## in this order — a crowbar is faster and kinder to the wood).
@export var remove_tools: Dictionary = {
	&"crowbar": {"seconds": 2.0, "plank_chance": 0.7, "nails_chance": 0.5},
	&"hammer": {"seconds": 4.0, "plank_chance": 0.5, "nails_chance": 0.3},
}
@export var remove_noise: StringName = &"hammering"

@export_group("Zombies and senses")
## Zombies banging on one opening at once (the rest wait their turn).
@export var max_attackers: int = 3
## Sound of a zombie hit on the planks / of a plank breaking.
@export var bang_noise: StringName = &"barricade_bang"
@export var break_noise: StringName = &"wood_break"
## Each plank multiplies sound passing through the opening by this.
@export var sound_factor_per_plank: float = 0.8
## From this many planks a window blocks line of sight.
@export var vision_block_planks: int = 2
## Navigation: extra path cost (m) per plank on a window link, so zombies
## pick an unbarricaded entry when one is reachable.
@export var nav_cost_per_plank: float = 8.0


## Max planks for a fixture kind (&"door" / &"window").
func max_planks_for(kind: StringName) -> int:
	return max_planks_door if kind == &"door" else max_planks_window


## Pure: "" when a plank can be nailed, else the reason shown in the prompt.
## Checked in this order: full, tool, planks, nails.
func missing_reason(planks: int, max_planks: int, has_tool: bool, material_count: int, nails_count: int) -> String:
	if planks >= max_planks:
		return "Fully barricaded"
	if not has_tool:
		return "Need a hammer"
	if material_count < material_per_plank:
		return "Need planks" if material_per_plank <= 1 else "Need %d planks" % material_per_plank
	if nails_count < nails_per_plank:
		return "Need %d nails" % nails_per_plank
	return ""


## Pure: room for one more plank?
static func can_add(planks: int, max_planks: int) -> bool:
	return planks < max_planks


## The remove_tools entry for the first matching tag in [tags] (or {}).
func remove_spec(tags: Array) -> Dictionary:
	for tag: StringName in remove_tools:
		if tags.has(tag):
			return remove_tools[tag]
	return {}


## Tool tags (in preference order) that can remove a barricade.
func remove_tool_tags() -> Array[StringName]:
	var out: Array[StringName] = []
	for t: StringName in remove_tools:
		out.append(t)
	return out


## Pure: what comes back from prying one plank off with [spec]:
## {plank: 0/1 × material_per_plank, nails: 0/nails_per_plank}. [r1] / [r2]
## are uniform 0..1 rolls (rng.randf()).
func remove_yield(spec: Dictionary, r1: float, r2: float) -> Dictionary:
	var planks := material_per_plank if r1 < float(spec.get("plank_chance", 0.0)) else 0
	var nails := nails_per_plank if r2 < float(spec.get("nails_chance", 0.0)) else 0
	return {"plank": planks, "nails": nails}


## Pure: nailing time at a carpentry [multiplier] (SkillComponent).
func build_seconds_for(multiplier: float) -> float:
	return build_seconds * maxf(multiplier, 0.1)


## Pure: fresh plank health at a carpentry health [multiplier].
func plank_health_for(multiplier: float) -> float:
	return plank_health * maxf(multiplier, 0.1)


## Pure: sound multiplier through an opening with [planks].
func sound_factor(planks: int) -> float:
	return pow(sound_factor_per_plank, maxi(planks, 0))


## Pure: does a window with [planks] block sight?
func vision_blocked(planks: int) -> bool:
	return planks >= vision_block_planks


## Pure: plank colour for a health fraction (1 = new, 0 = about to break).
func color_for(fraction: float) -> Color:
	return damaged_color.lerp(plank_color, clampf(fraction, 0.0, 1.0))


func validate() -> PackedStringArray:
	var out: PackedStringArray = []
	if plank_health <= 0.0:
		out.append("plank_health must be > 0")
	if max_planks_window <= 0 or max_planks_door <= 0:
		out.append("max planks must be > 0")
	if build_seconds <= 0.0:
		out.append("build_seconds must be > 0")
	if build_tool_tags.is_empty():
		out.append("no build tool")
	if remove_tools.is_empty():
		out.append("no remove tool")
	if max_attackers <= 0:
		out.append("max_attackers must be > 0")
	return out
