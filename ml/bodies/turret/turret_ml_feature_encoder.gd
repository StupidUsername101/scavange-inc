class_name TurretMLFeatureEncoder
extends RefCounted

const SCHEMA_VERSION = 5
const FEATURE_NAMES: Array[String] = [
	"yaw_sine",
	"yaw_cosine",
	"pitch_normalized",
	"yaw_velocity_normalized",
	"pitch_velocity_normalized",
	"health_ratio",
	"target_present",
	"target_is_combat",
	"target_is_shootable",
	"target_offset_local_x",
	"target_offset_local_y",
	"target_offset_local_z",
	"target_velocity_local_x",
	"target_velocity_local_y",
	"target_velocity_local_z",
	"target_direct_direction_local_x",
	"target_direct_direction_local_y",
	"target_direct_direction_local_z",
	"target_intercept_direction_local_x",
	"target_intercept_direction_local_y",
	"target_intercept_direction_local_z",
	"target_distance",
	"target_radius",
	"line_of_sight",
	"target_within_range",
	"target_within_pitch_arc",
	"aim_alignment",
	"intercept_yaw_error_normalized",
	"intercept_pitch_error_normalized",
	"cooldown_ready",
	"trigger_command",
	"previous_yaw_drive",
	"previous_pitch_drive",
	"previous_trigger",
	"episode_progress",
]
const FEATURE_COUNT = 35
const TARGET_OFFSET_SCALE_M = 40.0
const TARGET_VELOCITY_SCALE_MPS = 20.0
const TARGET_RADIUS_SCALE_M = 3.0
const MAXIMUM_YAW_SPEED_RADPS = 8.0
const MAXIMUM_PITCH_SPEED_RADPS = 8.0


static func encode(observation: Dictionary) -> PackedFloat64Array:
	if not TurretMLObservation.is_valid(observation):
		return PackedFloat64Array()
	var body: Dictionary = observation.get("body", {})
	var weapon: Dictionary = observation.get("weapon", {})
	var target: Dictionary = observation.get("target", {})
	var yaw = float(body.get("yaw_angle_radians", 0.0))
	var pitch = float(body.get("pitch_angle_radians", 0.0))
	var offset: Vector3 = target.get("offset_local", Vector3.ZERO)
	var velocity: Vector3 = target.get("velocity_local", Vector3.ZERO)
	var direct_direction: Vector3 = target.get("direct_direction_local", Vector3.ZERO)
	var intercept_direction: Vector3 = target.get("intercept_direction_local", Vector3.ZERO)
	var previous_commands: PackedFloat64Array = observation.get(
		"previous_commands",
		TurretMLAction.neutral_commands()
	)
	var result = PackedFloat64Array()
	result.resize(FEATURE_COUNT)
	var index = 0
	result[index] = sin(yaw); index += 1
	result[index] = cos(yaw); index += 1
	result[index] = clampf(pitch / (PI * 0.5), -1.0, 1.0); index += 1
	result[index] = clampf(float(body.get("yaw_velocity_radians_per_second", 0.0)) / MAXIMUM_YAW_SPEED_RADPS, -1.0, 1.0); index += 1
	result[index] = clampf(float(body.get("pitch_velocity_radians_per_second", 0.0)) / MAXIMUM_PITCH_SPEED_RADPS, -1.0, 1.0); index += 1
	result[index] = _unit_to_signed(float(body.get("health_ratio", 1.0))); index += 1
	result[index] = _unit_to_signed(1.0 if bool(target.get("present", false)) else 0.0); index += 1
	result[index] = _unit_to_signed(1.0 if bool(target.get("is_combat_target", false)) else 0.0); index += 1
	result[index] = _unit_to_signed(1.0 if bool(target.get("is_shootable_target", false)) else 0.0); index += 1
	for value in [offset.x, offset.y, offset.z]:
		result[index] = _scaled_signed(value, TARGET_OFFSET_SCALE_M); index += 1
	for value in [velocity.x, velocity.y, velocity.z]:
		result[index] = _scaled_signed(value, TARGET_VELOCITY_SCALE_MPS); index += 1
	for value in [direct_direction.x, direct_direction.y, direct_direction.z]:
		result[index] = clampf(value, -1.0, 1.0); index += 1
	for value in [intercept_direction.x, intercept_direction.y, intercept_direction.z]:
		result[index] = clampf(value, -1.0, 1.0); index += 1
	result[index] = _unsigned_to_signed(float(target.get("distance_m", 0.0)), TARGET_OFFSET_SCALE_M); index += 1
	result[index] = _unsigned_to_signed(float(target.get("radius_m", 0.0)), TARGET_RADIUS_SCALE_M); index += 1
	result[index] = _unit_to_signed(1.0 if bool(target.get("line_of_sight", false)) else 0.0); index += 1
	result[index] = _unit_to_signed(1.0 if bool(target.get("within_range", false)) else 0.0); index += 1
	result[index] = _unit_to_signed(1.0 if bool(target.get("within_pitch_arc", false)) else 0.0); index += 1
	result[index] = clampf(float(target.get("aim_alignment", -1.0)), -1.0, 1.0); index += 1
	result[index] = clampf(float(target.get("yaw_error_radians", 0.0)) / PI, -1.0, 1.0); index += 1
	result[index] = clampf(float(target.get("pitch_error_radians", 0.0)) / PI, -1.0, 1.0); index += 1
	result[index] = _unit_to_signed(float(weapon.get("cooldown_ready_ratio", 0.0))); index += 1
	result[index] = _unit_to_signed(float(weapon.get("trigger_command", 0.0))); index += 1
	for command in previous_commands:
		result[index] = clampf(command, -1.0, 1.0); index += 1
	result[index] = _unit_to_signed(float(observation.get("episode_progress", 0.0)))
	return result


static func feature_names() -> Array[String]:
	return FEATURE_NAMES.duplicate()


static func is_normalized(values: PackedFloat64Array) -> bool:
	if values.size() != FEATURE_COUNT:
		return false
	for value in values:
		if not is_finite(value) or value < -1.000001 or value > 1.000001:
			return false
	return true


static func _scaled_signed(value: float, scale: float) -> float:
	return clampf(value / maxf(scale, 0.000001), -1.0, 1.0)


static func _unsigned_to_signed(value: float, scale: float) -> float:
	return _unit_to_signed(clampf(value / maxf(scale, 0.000001), 0.0, 1.0))


static func _unit_to_signed(value: float) -> float:
	return clampf(value, 0.0, 1.0) * 2.0 - 1.0
