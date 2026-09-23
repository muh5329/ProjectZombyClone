class_name CharacterAnimator
extends Node
## Drives a Character's CharacterModel from gameplay state (child
## "Animator" of the Player; NPCs later). Visual only: reads, never writes
## gameplay state.
##
## Priority each physics tick: dead → death fall (kept); busy context →
## climb / eat / sleep / sit / search / bandage; MeleeCombat phase →
## windup_* (charging holds it) / strike_* timed to the phase lengths;
## recent damage → hit flinch; locomotion by effective mode and speed
## (sneak / walk / jog / sprint, idle / sneak_idle standing), speed-scaled
## so feet do not slide. Also shows the worn bag on the back (chest bone).

const LOCOMOTION := {
	MovementComponent.Mode.SNEAK: &"sneak", MovementComponent.Mode.WALK: &"walk",
	MovementComponent.Mode.JOG: &"jog", MovementComponent.Mode.SPRINT: &"sprint",
}
const BUSY := {
	&"climb": &"climb", &"eat": &"eat", &"drink": &"eat", &"sleep": &"sleep", &"rest": &"sit",
	&"search": &"search", &"bandage": &"bandage", &"clear_glass": &"search",
	&"barricade": &"hammer", &"unbarricade": &"hammer", &"disassemble": &"hammer",
	&"move_furniture": &"push",
}
## Seconds the busy climb takes (HouseWindow tween); the clip is scaled to it.
const CLIMB_SECONDS := 0.8
const MOVING_SPEED := 0.2
## Clip time of the strike's impact pose (strike_* clips).
const STRIKE_IMPACT := 0.55
const HIT_SECONDS := 0.35

@export var model_path: NodePath = ^"../Visual/Model"

var character: Character
var model: CharacterModel
var combat: MeleeCombat
var bag_visual: MeshInstance3D
var _straps: Array[MeshInstance3D] = []
var _phase: int = -1
var _hit_left: float = 0.0
## A new hit restarts the flinch even while it is still playing.
var _hit_restart: bool = false


func _ready() -> void:
	character = get_parent() as Character
	model = get_node_or_null(model_path) as CharacterModel
	combat = character.get_node_or_null("Combat") as MeleeCombat if character else null
	# The parent's @onready vars are not set yet (children are ready first).
	var health := character.get_node_or_null("Health") as HealthComponent if character else null
	if health:
		health.damaged.connect(_on_damaged)
	var eq := character.get_node_or_null("Equipment") if character else null
	if eq and eq.has_signal(&"equipped_changed"):
		eq.equipped_changed.connect(_on_equipped_changed)
		_refresh_bag.call_deferred()


## Pure: the locomotion clip + speed scale for a movement mode / speed.
static func locomotion_clip(mode: int, speed: float) -> Array:
	if speed < MOVING_SPEED:
		return [&"sneak_idle" if mode == MovementComponent.Mode.SNEAK else &"idle", 1.0]
	var clip: StringName = LOCOMOTION.get(mode, &"walk")
	return [clip, clampf(speed / float(CharacterAnimations.DESIGN_SPEED[clip]), 0.4, 1.8)]


## Pure: the clip for a busy context (&"" = none known → idle).
static func busy_clip(context: StringName) -> StringName:
	return BUSY.get(context, &"idle")


## Pure: [windup clip, strike clip] for a weapon.
static func swing_clips(w: WeaponData, is_fists: bool) -> Array[StringName]:
	var kind := &"1h"
	if w != null and w.is_shove:
		kind = &"shove"
	elif is_fists or w == null:
		kind = &"punch"
	elif w.two_handed:
		kind = &"2h"
	return [StringName("windup_%s" % kind), StringName("strike_%s" % kind)]


func _on_damaged(_amount: float, _source: Node, _info: Dictionary) -> void:
	_hit_left = HIT_SECONDS
	_hit_restart = true


func _physics_process(delta: float) -> void:
	if model == null or character == null:
		return
	_hit_left = maxf(_hit_left - delta, 0.0)
	_choose()
	model.advance(delta)


## Clip currently playing (tests).
func clip() -> StringName:
	return model.current if model else &""


func _choose() -> void:
	if character.is_dead() or character.busy_context == &"dead":
		model.play(&"death", 0.1)
		return
	if character.is_busy:
		var ctx := character.busy_context
		var c := busy_clip(ctx)
		model.play(c, 0.2, 1.0 / CLIMB_SECONDS if c == &"climb" else 1.0)
		_phase = -1
		return
	if combat and combat.phase != MeleeCombat.Phase.IDLE and combat.current != null:
		_combat_clip()
		return
	_phase = -1
	if _hit_left > 0.0:
		model.play(&"hit", 0.05, 1.0, _hit_restart)
		_hit_restart = false
		return
	var l := locomotion_clip(character.effective_mode, character.speed())
	model.play(l[0], 0.2, l[1])


func _combat_clip() -> void:
	var w := combat.current
	var clips := swing_clips(w, w == combat.fists)
	var ph := combat.phase
	var entered := ph != _phase
	_phase = ph
	match ph:
		MeleeCombat.Phase.CHARGING:
			model.play(clips[0], 0.12, 2.5)
		MeleeCombat.Phase.WINDUP:
			if entered:
				model.play(clips[0], 0.08, 1.0 / maxf(combat.phase_left, 0.05))
		MeleeCombat.Phase.ACTIVE:
			if entered:
				model.play(clips[1], 0.04, STRIKE_IMPACT / maxf(combat.phase_left, 0.05))
		MeleeCombat.Phase.RECOVERY:
			if entered:
				model.play(clips[1], 0.05, (1.0 - STRIKE_IMPACT) / maxf(combat.phase_left, 0.05))


# --- Worn bag -------------------------------------------------------------------

func _on_equipped_changed(slot: StringName, _item) -> void:
	if slot == &"back":
		_refresh_bag()


func _refresh_bag() -> void:
	if model == null or model.skeleton == null or character == null:
		return
	var eq := character.get_node_or_null("Equipment")
	var bag: ItemInstance = eq.back_bag() if eq and eq.has_method(&"back_bag") else null
	if bag == null:
		if bag_visual:
			bag_visual.visible = false
		for st in _straps:
			st.visible = false
		return
	if bag_visual == null:
		bag_visual = MeshInstance3D.new()
		bag_visual.name = "Bag"
		var holder := model.attach(&"chest")
		holder.add_child(bag_visual)
		bag_visual.material_override = StandardMaterial3D.new()
	var box := BoxMesh.new()
	var d := bag.data
	# Worn upright on the upper back; a duffel sits a little lower / wider.
	var duffel := d != null and String(d.id).contains("duffel")
	box.size = Vector3(0.36, 0.26, 0.2) if duffel else Vector3(0.3, 0.36, 0.16)
	bag_visual.mesh = box
	bag_visual.position = Vector3(0, -0.08 if duffel else -0.02, 0.115 + box.size.z * 0.5)
	var col := (d.color if d else Color(0.3, 0.35, 0.25)).darkened(0.4)
	(bag_visual.material_override as StandardMaterial3D).albedo_color = col
	_build_straps(col.darkened(0.2))
	bag_visual.visible = true
	for st in _straps:
		st.visible = true


## Shoulder straps: down the chest front and over the shoulders (chest bone).
func _build_straps(col: Color) -> void:
	if _straps.is_empty():
		var holder := model.attach(&"chest")
		var m := StandardMaterial3D.new()
		for sx in [-1.0, 1.0]:
			for part in [[Vector3(0.09 * sx, 0.02, -0.118), Vector3(0.035, 0.26, 0.012)],
					[Vector3(0.09 * sx, 0.165, 0.0), Vector3(0.035, 0.014, 0.25)]]:
				var mi := MeshInstance3D.new()
				mi.name = "Strap"
				var bm := BoxMesh.new()
				bm.size = part[1]
				mi.mesh = bm
				mi.position = part[0]
				mi.material_override = m
				holder.add_child(mi)
				_straps.append(mi)
	(_straps[0].material_override as StandardMaterial3D).albedo_color = col
