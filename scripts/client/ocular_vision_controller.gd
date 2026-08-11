extends ColorRect
class_name OcularVisionController

const DEFAULT_DISTORTION_CENTER := Vector2(0.5, 0.5)
const DEFAULT_PULSE_HZ := 7.0
const MIN_PULSE_HZ := 0.1
const MAX_PULSE_HZ := 30.0
const MIN_FRAME_DELTA := 0.000001
const FULL_MOTION_ANGULAR_SPEED := 5.2
const MOTION_SMOOTHING_RATE := 13.0
const DISTORTION_SMOOTHING_RATE := 10.0

#######################################################
# Applies the equipped ocular shader, blindness, quality artifacts, and bounded temporary
# distortion to the local view.
#######################################################

var eye_definition_path := ""
var eye_definition: EyeDefinition
var vision_material: ShaderMaterial
var external_distortion := Vector3.ZERO
var target_external_distortion := Vector3.ZERO
var distortion_center := DEFAULT_DISTORTION_CENTER
var target_distortion_center := DEFAULT_DISTORTION_CENTER
var pulse_hz := DEFAULT_PULSE_HZ
var last_view_rotation := Vector2.ZERO
var has_view_sample := false
var motion_intensity := 0.0
var special_sight_effects: Array[StringName] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.BLACK


func set_eye_entry(entry: Dictionary) -> bool:
	var definition_path := str(entry.get("definition_path", ""))
	if definition_path == eye_definition_path:
		return eye_definition != null

	eye_definition_path = definition_path
	eye_definition = null
	vision_material = null
	material = null
	color = Color.BLACK
	special_sight_effects.clear()

	if definition_path.is_empty():
		return false

	var loaded_definition := load(definition_path)
	eye_definition = loaded_definition as EyeDefinition
	if eye_definition == null or eye_definition.vision_shader == null:
		push_error("Invalid ocular definition: %s" % definition_path)
		return false

	vision_material = ShaderMaterial.new()
	vision_material.shader = eye_definition.vision_shader
	var vision_parameters := eye_definition.get_vision_parameters()
	for parameter_value: Variant in vision_parameters.keys():
		var parameter_name := str(parameter_value)
		vision_material.set_shader_parameter(
			parameter_name,
			vision_parameters[parameter_value]
		)
	material = vision_material
	color = Color.WHITE
	special_sight_effects = eye_definition.special_sight_effects.duplicate()
	_apply_dynamic_parameters()
	return true


func apply_distortion_state(state: Dictionary) -> void:
	target_external_distortion = Vector3(
		clampf(SafeVariant.finite_float_or(state.get("warp", 0.0), 0.0), 0.0, 1.0),
		clampf(SafeVariant.finite_float_or(state.get("glitch", 0.0), 0.0), 0.0, 1.0),
		clampf(SafeVariant.finite_float_or(state.get("smear", 0.0), 0.0), 0.0, 1.0)
	)
	var center: Vector2 = SafeVariant.vector2_strict_or(
		state.get("center", DEFAULT_DISTORTION_CENTER),
		DEFAULT_DISTORTION_CENTER
	)
	target_distortion_center = Vector2(
		clampf(center.x, 0.0, 1.0),
		clampf(center.y, 0.0, 1.0)
	)
	pulse_hz = clampf(
		SafeVariant.finite_float_or(state.get("pulse_hz", DEFAULT_PULSE_HZ), DEFAULT_PULSE_HZ),
		MIN_PULSE_HZ,
		MAX_PULSE_HZ
	)


func update_view(yaw: float, pitch: float, delta: float) -> void:
	var view_rotation := Vector2(yaw, pitch)
	if not has_view_sample or delta <= MIN_FRAME_DELTA:
		last_view_rotation = view_rotation
		has_view_sample = true
	else:
		var yaw_delta := absf(
			wrapf(view_rotation.x - last_view_rotation.x, -PI, PI)
		)
		var pitch_delta := absf(view_rotation.y - last_view_rotation.y)
		var angular_speed := (yaw_delta + pitch_delta) / delta
		var target_motion := clampf(
			angular_speed / FULL_MOTION_ANGULAR_SPEED,
			0.0,
			1.0
		)
		var motion_weight := 1.0 - exp(
			-delta * MOTION_SMOOTHING_RATE
		)
		motion_intensity = lerpf(
			motion_intensity,
			target_motion,
			motion_weight
		)
		last_view_rotation = view_rotation

	var distortion_weight := 1.0 - exp(
		-delta * DISTORTION_SMOOTHING_RATE
	)
	external_distortion = external_distortion.lerp(
		target_external_distortion,
		distortion_weight
	)
	distortion_center = distortion_center.lerp(
		target_distortion_center,
		distortion_weight
	)
	_apply_dynamic_parameters()


func supports_special_sight(effect_id: StringName) -> bool:
	return special_sight_effects.has(effect_id)


func _apply_dynamic_parameters() -> void:
	if vision_material == null:
		return
	vision_material.set_shader_parameter(
		"motion_intensity",
		motion_intensity
	)
	vision_material.set_shader_parameter(
		"external_distortion",
		external_distortion.x
	)
	vision_material.set_shader_parameter(
		"external_glitch",
		external_distortion.y
	)
	vision_material.set_shader_parameter(
		"external_smear",
		external_distortion.z
	)
	vision_material.set_shader_parameter(
		"distortion_center",
		distortion_center
	)
	vision_material.set_shader_parameter("pulse_hz", pulse_hz)
