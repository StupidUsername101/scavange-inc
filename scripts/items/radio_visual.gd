@tool
extends Node3D

const CONE_ATTACK_SPEED := 96.0
const CONE_RELEASE_SPEED := 28.0
const MAX_CONE_RADIAL_SCALE := 0.055
const MAX_CONE_DEPTH_SCALE := 0.024
const MAX_CONE_EXCURSION := 0.010

## Presentation hook used by ItemProxy's generic replicated-state propagation. The authoritative
## state controls power; the local radio voice supplies a cached music envelope for the cone.

var _item_id := -1
var _powered := false
var _cone_level := 0.0
var _speaker_cone: MeshInstance3D
var _speaker_rest_scale := Vector3.ONE
var _speaker_rest_position := Vector3.ZERO


func _ready() -> void:
	_speaker_cone = get_node_or_null("SpeakerCone") as MeshInstance3D
	if _speaker_cone != null:
		_speaker_rest_scale = _speaker_cone.scale
		_speaker_rest_position = _speaker_cone.position
	set_process(not Engine.is_editor_hint())


func apply_server_item_state(state: Dictionary) -> void:
	_item_id = SafeVariant.integral_int_or(state.get("item_id"), -1)
	_powered = SafeVariant.strict_bool_or(state.get("radio_powered"), false)
	var power_light := get_node_or_null("PowerLight") as GeometryInstance3D
	if power_light != null:
		power_light.visible = _powered


func _process(delta: float) -> void:
	var target_level := 0.0
	if _powered and _item_id >= 0:
		var renderer := Client.get("radio_audio_renderer") as RadioAudioRenderer
		if is_instance_valid(renderer):
			target_level = renderer.get_music_visual_level(_item_id)
	var response_speed := (
		CONE_ATTACK_SPEED
		if target_level > _cone_level
		else CONE_RELEASE_SPEED
	)
	_cone_level = lerpf(
		_cone_level,
		target_level,
		1.0 - exp(-response_speed * maxf(delta, 0.0))
	)
	_apply_cone_level(_cone_level)


func _apply_cone_level(level: float) -> void:
	if _speaker_cone == null:
		return
	var safe_level := clampf(level, 0.0, 1.0)
	var radial_scale := 1.0 + MAX_CONE_RADIAL_SCALE * safe_level
	_speaker_cone.scale = Vector3(
		_speaker_rest_scale.x * radial_scale,
		_speaker_rest_scale.y * (1.0 + MAX_CONE_DEPTH_SCALE * safe_level),
		_speaker_rest_scale.z * radial_scale
	)
	_speaker_cone.position = _speaker_rest_position + Vector3(
		0.0,
		0.0,
		MAX_CONE_EXCURSION * safe_level
	)
