@tool
class_name TurretBaseDefinition
extends TurretPartDefinition

@export_group("Geometry")
@export var footprint_size = Vector3(0.9, 0.35, 0.9)
@export_range(0.05, 5.0, 0.01, "or_greater") var rotating_head_radius_m = 0.32
@export_range(0.05, 5.0, 0.01, "or_greater") var rotating_head_height_m = 0.28
@export_range(0.0, 5.0, 0.01, "or_greater") var head_center_height_m = 0.48

@export_group("Yaw drive")
@export_range(1.0, 720.0, 0.5, "or_greater") var maximum_yaw_speed_degrees_per_second = 110.0
@export_range(1.0, 2000.0, 0.5, "or_greater") var yaw_acceleration_degrees_per_second_squared = 360.0
@export_range(0.0, 2000.0, 0.5, "or_greater") var yaw_braking_degrees_per_second_squared = 240.0


func _init() -> void:
	display_name = "Training Servo Base"
	mass_kg = 28.0
	maximum_health = 300.0


func sanitize() -> void:
	footprint_size = Vector3(
		maxf(absf(footprint_size.x), 0.05),
		maxf(absf(footprint_size.y), 0.05),
		maxf(absf(footprint_size.z), 0.05)
	)
	rotating_head_radius_m = maxf(rotating_head_radius_m, 0.05)
	rotating_head_height_m = maxf(rotating_head_height_m, 0.05)
	head_center_height_m = maxf(head_center_height_m, footprint_size.y * 0.5)
	maximum_yaw_speed_degrees_per_second = maxf(maximum_yaw_speed_degrees_per_second, 1.0)
	yaw_acceleration_degrees_per_second_squared = maxf(yaw_acceleration_degrees_per_second_squared, 1.0)
	yaw_braking_degrees_per_second_squared = maxf(yaw_braking_degrees_per_second_squared, 0.0)


func to_dictionary() -> Dictionary:
	var result = super.to_dictionary()
	result.merge({
		"footprint_size": TurretPartDefinition.vector3_to_json(footprint_size),
		"rotating_head_radius_m": rotating_head_radius_m,
		"rotating_head_height_m": rotating_head_height_m,
		"head_center_height_m": head_center_height_m,
		"maximum_yaw_speed_degrees_per_second": maximum_yaw_speed_degrees_per_second,
		"yaw_acceleration_degrees_per_second_squared": yaw_acceleration_degrees_per_second_squared,
		"yaw_braking_degrees_per_second_squared": yaw_braking_degrees_per_second_squared,
	})
	return result


static func from_dictionary(value: Dictionary) -> TurretBaseDefinition:
	var result = TurretBaseDefinition.new()
	result.display_name = str(value.get("display_name", result.display_name))
	result.mass_kg = maxf(TurretPartDefinition.finite_float_or(value.get("mass_kg"), result.mass_kg), 0.0)
	result.maximum_health = maxf(TurretPartDefinition.finite_float_or(value.get("maximum_health"), result.maximum_health), 1.0)
	result.footprint_size = TurretPartDefinition.vector3_from_json(
		value.get("footprint_size"),
		result.footprint_size
	)
	result.rotating_head_radius_m = maxf(TurretPartDefinition.finite_float_or(value.get("rotating_head_radius_m"), result.rotating_head_radius_m), 0.05)
	result.rotating_head_height_m = maxf(TurretPartDefinition.finite_float_or(value.get("rotating_head_height_m"), result.rotating_head_height_m), 0.05)
	result.head_center_height_m = maxf(TurretPartDefinition.finite_float_or(value.get("head_center_height_m"), result.head_center_height_m), 0.0)
	result.maximum_yaw_speed_degrees_per_second = maxf(TurretPartDefinition.finite_float_or(value.get("maximum_yaw_speed_degrees_per_second"), result.maximum_yaw_speed_degrees_per_second), 1.0)
	result.yaw_acceleration_degrees_per_second_squared = maxf(TurretPartDefinition.finite_float_or(value.get("yaw_acceleration_degrees_per_second_squared"), result.yaw_acceleration_degrees_per_second_squared), 1.0)
	result.yaw_braking_degrees_per_second_squared = maxf(TurretPartDefinition.finite_float_or(value.get("yaw_braking_degrees_per_second_squared"), result.yaw_braking_degrees_per_second_squared), 0.0)
	result.sanitize()
	return result


func ml_part_tags() -> Array[StringName]:
	return [&"turret_part", &"turret_base"]


func ml_control_descriptors() -> Array[Dictionary]:
	return [{
		"name": "yaw",
		"kind": "angular_velocity",
		"minimum": -1.0,
		"maximum": 1.0,
		"neutral": 0.0,
	}]


func ml_observation_descriptors() -> Array[Dictionary]:
	return [
		{"name": "yaw_sin", "minimum": -1.0, "maximum": 1.0},
		{"name": "yaw_cos", "minimum": -1.0, "maximum": 1.0},
		{"name": "yaw_velocity", "minimum": -1.0, "maximum": 1.0},
	]


func ml_encode_observation(runtime_state: Variant, _host_state: Dictionary = {}) -> PackedFloat64Array:
	var state: Dictionary = runtime_state if runtime_state is Dictionary else {}
	var yaw: float = float(state.get("yaw_angle_radians", 0.0))
	var velocity: float = float(state.get("yaw_velocity_radians_per_second", 0.0))
	var speed_scale: float = maxf(deg_to_rad(maximum_yaw_speed_degrees_per_second), 0.000001)
	if not is_finite(yaw) or not is_finite(velocity):
		return PackedFloat64Array()
	return PackedFloat64Array([
		sin(yaw),
		cos(yaw),
		clampf(velocity / speed_scale, -1.0, 1.0),
	])
