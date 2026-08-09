@tool
class_name TurretGunDefinition
extends TurretPartDefinition

@export_group("Geometry")
@export_range(0.1, 10.0, 0.01, "or_greater") var barrel_length_m = 1.15
@export_range(0.01, 1.0, 0.005, "or_greater") var barrel_radius_m = 0.075
@export var barrel_mount_offset = Vector3(0.0, 0.08, 0.0)

@export_group("Pitch drive")
@export_range(-89.0, 89.0, 0.5) var minimum_pitch_degrees = -12.0
@export_range(-89.0, 89.0, 0.5) var maximum_pitch_degrees = 68.0
@export_range(1.0, 720.0, 0.5, "or_greater") var maximum_pitch_speed_degrees_per_second = 85.0
@export_range(1.0, 2000.0, 0.5, "or_greater") var pitch_acceleration_degrees_per_second_squared = 300.0
@export_range(0.0, 2000.0, 0.5, "or_greater") var pitch_braking_degrees_per_second_squared = 220.0

@export_group("Weapon")
@export_range(0.01, 10.0, 0.01, "or_greater") var seconds_between_shots = 0.32
@export_range(1.0, 1000.0, 1.0, "or_greater") var projectile_speed_mps = 48.0
@export_range(0.1, 1000.0, 0.1, "or_greater") var projectile_damage = 18.0
@export_range(1.0, 1000.0, 0.5, "or_greater") var maximum_range_m = 80.0
@export_range(0.0, 20.0, 0.01, "or_greater") var spread_degrees = 0.15
@export_range(0.0, 1.0, 0.01) var trigger_threshold = 0.55


func _init() -> void:
	display_name = "Training Autocannon"
	mass_kg = 12.0
	maximum_health = 180.0


func sanitize() -> void:
	barrel_length_m = maxf(barrel_length_m, 0.1)
	barrel_radius_m = maxf(barrel_radius_m, 0.01)
	minimum_pitch_degrees = clampf(minimum_pitch_degrees, -89.0, 88.0)
	maximum_pitch_degrees = clampf(maximum_pitch_degrees, minimum_pitch_degrees + 1.0, 89.0)
	maximum_pitch_speed_degrees_per_second = maxf(maximum_pitch_speed_degrees_per_second, 1.0)
	pitch_acceleration_degrees_per_second_squared = maxf(pitch_acceleration_degrees_per_second_squared, 1.0)
	pitch_braking_degrees_per_second_squared = maxf(pitch_braking_degrees_per_second_squared, 0.0)
	seconds_between_shots = maxf(seconds_between_shots, 0.01)
	projectile_speed_mps = maxf(projectile_speed_mps, 1.0)
	projectile_damage = maxf(projectile_damage, 0.1)
	maximum_range_m = maxf(maximum_range_m, 1.0)
	spread_degrees = maxf(spread_degrees, 0.0)
	trigger_threshold = clampf(trigger_threshold, 0.0, 1.0)


func to_dictionary() -> Dictionary:
	var result = super.to_dictionary()
	result.merge({
		"barrel_length_m": barrel_length_m,
		"barrel_radius_m": barrel_radius_m,
		"barrel_mount_offset": TurretPartDefinition.vector3_to_json(barrel_mount_offset),
		"minimum_pitch_degrees": minimum_pitch_degrees,
		"maximum_pitch_degrees": maximum_pitch_degrees,
		"maximum_pitch_speed_degrees_per_second": maximum_pitch_speed_degrees_per_second,
		"pitch_acceleration_degrees_per_second_squared": pitch_acceleration_degrees_per_second_squared,
		"pitch_braking_degrees_per_second_squared": pitch_braking_degrees_per_second_squared,
		"seconds_between_shots": seconds_between_shots,
		"projectile_speed_mps": projectile_speed_mps,
		"projectile_damage": projectile_damage,
		"maximum_range_m": maximum_range_m,
		"spread_degrees": spread_degrees,
		"trigger_threshold": trigger_threshold,
	})
	return result


static func from_dictionary(value: Dictionary) -> TurretGunDefinition:
	var result = TurretGunDefinition.new()
	result.display_name = str(value.get("display_name", result.display_name))
	result.mass_kg = maxf(TurretPartDefinition.finite_float_or(value.get("mass_kg"), result.mass_kg), 0.0)
	result.maximum_health = maxf(TurretPartDefinition.finite_float_or(value.get("maximum_health"), result.maximum_health), 1.0)
	result.barrel_length_m = maxf(TurretPartDefinition.finite_float_or(value.get("barrel_length_m"), result.barrel_length_m), 0.1)
	result.barrel_radius_m = maxf(TurretPartDefinition.finite_float_or(value.get("barrel_radius_m"), result.barrel_radius_m), 0.01)
	result.barrel_mount_offset = TurretPartDefinition.vector3_from_json(
		value.get("barrel_mount_offset"),
		result.barrel_mount_offset
	)
	result.minimum_pitch_degrees = TurretPartDefinition.finite_float_or(value.get("minimum_pitch_degrees"), result.minimum_pitch_degrees)
	result.maximum_pitch_degrees = TurretPartDefinition.finite_float_or(value.get("maximum_pitch_degrees"), result.maximum_pitch_degrees)
	result.maximum_pitch_speed_degrees_per_second = maxf(TurretPartDefinition.finite_float_or(value.get("maximum_pitch_speed_degrees_per_second"), result.maximum_pitch_speed_degrees_per_second), 1.0)
	result.pitch_acceleration_degrees_per_second_squared = maxf(TurretPartDefinition.finite_float_or(value.get("pitch_acceleration_degrees_per_second_squared"), result.pitch_acceleration_degrees_per_second_squared), 1.0)
	result.pitch_braking_degrees_per_second_squared = maxf(TurretPartDefinition.finite_float_or(value.get("pitch_braking_degrees_per_second_squared"), result.pitch_braking_degrees_per_second_squared), 0.0)
	result.seconds_between_shots = maxf(TurretPartDefinition.finite_float_or(value.get("seconds_between_shots"), result.seconds_between_shots), 0.01)
	result.projectile_speed_mps = maxf(TurretPartDefinition.finite_float_or(value.get("projectile_speed_mps"), result.projectile_speed_mps), 1.0)
	result.projectile_damage = maxf(TurretPartDefinition.finite_float_or(value.get("projectile_damage"), result.projectile_damage), 0.1)
	result.maximum_range_m = maxf(TurretPartDefinition.finite_float_or(value.get("maximum_range_m"), result.maximum_range_m), 1.0)
	result.spread_degrees = maxf(TurretPartDefinition.finite_float_or(value.get("spread_degrees"), result.spread_degrees), 0.0)
	result.trigger_threshold = clampf(TurretPartDefinition.finite_float_or(value.get("trigger_threshold"), result.trigger_threshold), 0.0, 1.0)
	result.sanitize()
	return result


func ml_part_tags() -> Array[StringName]:
	return [&"turret_part", &"gun"]


func ml_control_descriptors() -> Array[Dictionary]:
	return [
		{"name": "pitch", "kind": "angular_velocity", "minimum": -1.0, "maximum": 1.0, "neutral": 0.0},
		{"name": "trigger", "kind": "trigger", "minimum": 0.0, "maximum": 1.0, "neutral": 0.0},
	]


func ml_observation_descriptors() -> Array[Dictionary]:
	return [
		{"name": "pitch", "minimum": -1.0, "maximum": 1.0},
		{"name": "pitch_velocity", "minimum": -1.0, "maximum": 1.0},
		{"name": "cooldown", "minimum": -1.0, "maximum": 1.0},
	]


func ml_encode_observation(runtime_state: Variant, _host_state: Dictionary = {}) -> PackedFloat64Array:
	var state: Dictionary = runtime_state if runtime_state is Dictionary else {}
	var pitch: float = float(state.get("pitch_angle_radians", 0.0))
	var velocity: float = float(state.get("pitch_velocity_radians_per_second", 0.0))
	var cooldown: float = float(state.get("shot_cooldown_seconds", 0.0))
	if not is_finite(pitch) or not is_finite(velocity) or not is_finite(cooldown):
		return PackedFloat64Array()
	var minimum_pitch: float = deg_to_rad(minimum_pitch_degrees)
	var maximum_pitch: float = deg_to_rad(maximum_pitch_degrees)
	var pitch_normalized: float = (pitch - minimum_pitch) / maxf(maximum_pitch - minimum_pitch, 0.000001)
	var speed_scale: float = maxf(deg_to_rad(maximum_pitch_speed_degrees_per_second), 0.000001)
	var cooldown_ratio: float = clampf(cooldown / maxf(seconds_between_shots, 0.000001), 0.0, 1.0)
	return PackedFloat64Array([
		clampf(pitch_normalized, 0.0, 1.0) * 2.0 - 1.0,
		clampf(velocity / speed_scale, -1.0, 1.0),
		cooldown_ratio * 2.0 - 1.0,
	])
