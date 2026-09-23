class_name CharacterModel
extends Node3D
## A procedural person in the scene: Skeleton3D (HumanoidBuilder bones) +
## skinned MeshInstance3D (shared mesh / skin / materials from CharacterAssets)
## + an AnimationPlayer in MANUAL process mode with the shared procedural
## AnimationLibrary. The owner (CharacterAnimator / ZombieVisual) picks the
## clip with play() and advances time with advance() at whatever rate it
## can afford (distant zombies update less often). Visual only.
##
## Children are built in code: "Skeleton3D" (with "Body" mesh under it) and
## "AnimationPlayer". Attachments (weapon in the right hand, bag on the
## back) are BoneAttachment3D nodes made by attach().

## Outfit for a hand-placed model (the player); ignored when setup() is
## called with an explicit Appearance.
@export var outfit: Outfit
@export var skin_tone: int = 1
@export var hair_style: StringName = &"short"
@export var hair_color: int = 2

var skeleton: Skeleton3D
var body: MeshInstance3D
var anim: AnimationPlayer
var appearance: Appearance
var current: StringName = &""
var _attachments: Dictionary = {}


func _ready() -> void:
	if skeleton == null and appearance != null:
		setup(appearance)
	elif skeleton == null:
		var a := Appearance.new()
		a.outfit = outfit if outfit else Outfit.new()
		a.skin = Appearance.SKIN_TONES[posmod(skin_tone, Appearance.SKIN_TONES.size())]
		a.hair_style = hair_style
		a.hair_color = Appearance.HAIR_COLORS[posmod(hair_color, Appearance.HAIR_COLORS.size())]
		setup(a)


## Build (or rebuild) the model for [app].
func setup(app: Appearance) -> void:
	appearance = app
	var assets := CharacterAssets.of(get_tree()) if is_inside_tree() else null
	if assets == null:
		push_error("CharacterModel.setup needs the scene tree")
		return
	if skeleton == null:
		skeleton = HumanoidBuilder.build_skeleton()
		add_child(skeleton)
		body = MeshInstance3D.new()
		body.name = "Body"
		skeleton.add_child(body)
		body.skeleton = NodePath("..")
		body.skin = assets.skin
		anim = AnimationPlayer.new()
		anim.name = "AnimationPlayer"
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		add_child(anim)
		anim.add_animation_library(&"", assets.library)
	body.mesh = assets.mesh_for(app)
	scale = Vector3.ONE * app.height_scale
	current = &""


## Start [clip] (cross-fading [blend] s) at [speed]; no-op when it is
## already playing (only the speed changes). [restart] replays it.
func play(clip: StringName, blend: float = 0.2, speed: float = 1.0, restart: bool = false) -> void:
	if anim == null:
		return
	anim.speed_scale = speed
	if clip == current and not restart and (anim.is_playing() or not anim.has_animation(clip) or anim.get_animation(clip).loop_mode == Animation.LOOP_NONE):
		return
	current = clip
	if restart and anim.current_animation == String(clip):
		anim.stop(true)
	anim.play(clip, blend)


func set_speed(speed: float) -> void:
	if anim:
		anim.speed_scale = speed


## Advance the animation by [dt] seconds (manual process mode).
func advance(dt: float) -> void:
	if anim and anim.is_playing():
		anim.advance(dt)


## Jump the current clip to its end (corpses spawned already dead).
func finish() -> void:
	if anim and anim.current_animation != "":
		anim.seek(anim.current_animation_length, true)


func is_finished() -> bool:
	return anim == null or not anim.is_playing()


## Seconds into the current clip.
func clip_position() -> float:
	return anim.current_animation_position if anim and anim.current_animation != "" else 0.0


## Surface 1 (eyes) mood material (zombies).
func set_eye_material(m: Material) -> void:
	if body:
		body.set_surface_override_material(HumanoidBuilder.SURFACE_EYES, m)


func eye_material() -> Material:
	return body.get_surface_override_material(HumanoidBuilder.SURFACE_EYES) if body else null


## Body-surface override (hit tint); null restores. The eyes keep their
## mood material.
func set_body_material(m: Material) -> void:
	if body:
		body.set_surface_override_material(HumanoidBuilder.SURFACE_BODY, m)


## A BoneAttachment3D following [bone] (created once per bone).
func attach(bone: StringName) -> BoneAttachment3D:
	if _attachments.has(bone):
		return _attachments[bone]
	var ba := BoneAttachment3D.new()
	ba.name = "Attach_%s" % bone
	ba.bone_name = bone
	skeleton.add_child(ba)
	_attachments[bone] = ba
	return ba


## World position of a bone's joint (current pose).
func bone_global_position(bone: StringName) -> Vector3:
	var i := skeleton.find_bone(bone)
	return skeleton.global_transform * skeleton.get_bone_global_pose(i).origin


## Current pose rotation of [bone] (tests).
func bone_pose_rotation(bone: StringName) -> Quaternion:
	return skeleton.get_bone_pose_rotation(skeleton.find_bone(bone))
