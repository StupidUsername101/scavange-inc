class_name DroneMLFeatureEncoder
extends RefCounted

const GLOBAL_FEATURE_NAMES: Array[String] = [
	"linear_velocity_local_x", "linear_velocity_local_y", "linear_velocity_local_z",
	"angular_velocity_local_x", "angular_velocity_local_y", "angular_velocity_local_z",
	"body_up_world_x", "body_up_world_y", "body_up_world_z",
	"target_present", "target_offset_local_x", "target_offset_local_y",
	"target_offset_local_z", "target_velocity_local_x",
	"target_velocity_local_y", "target_velocity_local_z",
	"target_hover_radius_m", "target_distance_m",
	"target_direction_local_x", "target_direction_local_y",
	"target_direction_local_z", "target_boundary_error_m",
	"target_inside_radius",
	"mass_kg", "inertia_x", "inertia_y", "inertia_z", "health",
	"battery_energy_wh", "battery_charge_ratio", "bus_voltage_v",
	"available_power_w", "power_spool_ratio", "spike_multiplier",
	"air_density_kg_m3", "wind_velocity_local_x", "wind_velocity_local_y",
	"wind_velocity_local_z", "ground_detected", "ground_clearance_m",
]
const PROPELLER_FEATURE_NAMES: Array[String] = [
	"installed", "slot_index", "position_local_x", "position_local_y",
	"position_local_z", "lift_axis_local_x", "lift_axis_local_y",
	"lift_axis_local_z", "spin_direction", "mass_kg", "rated_voltage_v",
	"supplied_voltage_v", "maximum_power_draw_w", "rotor_radius_m",
	"disk_area_m2", "aerodynamic_efficiency", "commanded_thrust_n",
	"requested_power_w", "applied_power_w", "realized_thrust_n",
	"maximum_static_thrust_n",
]

#######################################################
# Converts the readable snapshot into numeric global and per-propeller feature tensors while
# preserving names and a variable first dimension for arbitrary rotor topologies.
#######################################################


static func encode(observation: Dictionary) -> Dictionary:
	var body: Dictionary = observation.get("body", {})
	var electrical: Dictionary = observation.get("electrical", {})
	var environment: Dictionary = observation.get("environment", {})
	var objective: Dictionary = observation.get("objective", {})
	var basis: Basis = body.get("basis_world", Basis.IDENTITY)
	var target_state = _target_state(objective)
	var target_offset_world = Vector3.ZERO
	var target_velocity_world = Vector3.ZERO
	var target_hover_radius = 0.0
	if target_state["present"]:
		var target_position: Vector3 = target_state["position"]
		target_offset_world = target_position - body.get(
			"position_world", Vector3.ZERO
		)
		target_velocity_world = target_state["velocity"]
		target_hover_radius = maxf(
			float(objective.get("target_hover_radius_m", 0.0)),
			0.0
		)
	var target_offset_local = basis.inverse() * target_offset_world
	var target_velocity_local = basis.inverse() * target_velocity_world
	var target_distance = target_offset_world.length()
	var target_direction_local = (
		target_offset_local / target_distance
		if target_state["present"] and target_distance > 0.000001
		else Vector3.ZERO
	)
	var wind_velocity_local = basis.inverse() * environment.get(
		"wind_velocity_world", Vector3.ZERO
	)
	var global_features = PackedFloat32Array()
	_append_vector3(global_features, body.get("linear_velocity_local", Vector3.ZERO))
	_append_vector3(global_features, body.get("angular_velocity_local", Vector3.ZERO))
	_append_vector3(global_features, body.get("up_world", Vector3.UP))
	global_features.append(1.0 if target_state["present"] else 0.0)
	_append_vector3(global_features, target_offset_local)
	_append_vector3(global_features, target_velocity_local)
	global_features.append(target_hover_radius)
	global_features.append(target_distance)
	_append_vector3(global_features, target_direction_local)
	global_features.append(target_distance - target_hover_radius)
	global_features.append(
		1.0
		if target_state["present"] and target_distance <= target_hover_radius
		else 0.0
	)
	global_features.append(float(body.get("mass_kg", 0.0)))
	_append_vector3(global_features, body.get("inertia_kg_m2", Vector3.ZERO))
	global_features.append(float(body.get("health", 0.0)))
	global_features.append(float(electrical.get("battery_energy_wh", 0.0)))
	global_features.append(float(electrical.get("battery_charge_ratio", 0.0)))
	global_features.append(float(electrical.get("bus_voltage_v", 0.0)))
	global_features.append(float(electrical.get("available_power_w", 0.0)))
	global_features.append(float(electrical.get("power_spool_ratio", 0.0)))
	global_features.append(float(electrical.get("spike_multiplier", 1.0)))
	global_features.append(float(environment.get("air_density_kg_m3", 0.0)))
	_append_vector3(global_features, wind_velocity_local)
	global_features.append(1.0 if environment.get("ground_detected", false) else 0.0)
	global_features.append(float(environment.get("ground_clearance_m", 0.0)))

	var propeller_features: Array[PackedFloat32Array] = []
	for propeller: Dictionary in observation.get("propellers", []):
		propeller_features.append(_encode_propeller(propeller))
	return {
		"global_feature_names": GLOBAL_FEATURE_NAMES,
		"global_features": global_features,
		"propeller_feature_names": PROPELLER_FEATURE_NAMES,
		"propeller_features": propeller_features,
		"propeller_count": propeller_features.size(),
	}


static func _encode_propeller(propeller: Dictionary) -> PackedFloat32Array:
	var result = PackedFloat32Array()
	result.append(1.0 if propeller.get("installed", false) else 0.0)
	result.append(float(propeller.get("slot_index", -1)))
	_append_vector3(result, propeller.get("position_local", Vector3.ZERO))
	_append_vector3(result, propeller.get("lift_axis_local", Vector3.UP))
	result.append(float(propeller.get("spin_direction", 0)))
	for key: String in [
		"mass_kg", "rated_voltage_v", "supplied_voltage_v",
		"maximum_power_draw_w", "rotor_radius_m", "disk_area_m2",
		"aerodynamic_efficiency", "commanded_thrust_n", "requested_power_w",
		"applied_power_w", "realized_thrust_n", "maximum_static_thrust_n",
	]:
		result.append(float(propeller.get(key, 0.0)))
	return result


static func _target_state(objective: Dictionary) -> Dictionary:
	for key: String in ["target_position_world", "movement_target"]:
		var value = objective.get(key)
		if value is Vector3:
			return {
				"present": true,
				"position": value,
				"velocity": _target_velocity(objective),
			}
	return {
		"present": false,
		"position": Vector3.ZERO,
		"velocity": Vector3.ZERO,
	}


static func _target_velocity(objective: Dictionary) -> Vector3:
	for key: String in ["target_velocity_world", "movement_target_velocity"]:
		var value = objective.get(key)
		if value is Vector3:
			return value
	return Vector3.ZERO


static func _append_vector3(target: PackedFloat32Array, value: Vector3) -> void:
	target.append(value.x)
	target.append(value.y)
	target.append(value.z)
