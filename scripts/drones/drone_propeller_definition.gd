@tool
class_name DronePropellerDefinition
extends DronePartDefinition

#######################################################
# Defines the serialized drone propeller configuration shared by gameplay, inspection, and
# replication systems.
#######################################################

@export_group("Power")
@export_range(0.0, 100000.0, 0.1, "or_greater") var max_power_draw := 30.0

@export_group("Rotor")
@export_range(0.01, 100.0, 0.01, "or_greater") var rotor_radius := 0.18
@export_range(0.01, 1.0, 0.01) var aerodynamic_efficiency := 0.7
@export_range(0.0, 10.0, 0.001, "or_greater") var reaction_torque_per_newton := 0.012
@export_range(0.0, 5.0, 0.01, "or_greater") var axial_flow_response := 0.65
@export_range(0.0, 1.0, 0.01) var minimum_axial_flow_factor := 0.55
@export_range(1.0, 5.0, 0.01, "or_greater") var maximum_axial_flow_factor := 1.45


func get_disk_area() -> float:
	return PI * rotor_radius * rotor_radius


func ml_part_tags() -> Array[StringName]:
	return [&"drone_part", &"propeller"]


func ml_control_descriptors() -> Array[Dictionary]:
	return [{
		"name": "throttle",
		"kind": "propeller_throttle",
		"minimum": 0.0,
		"maximum": 1.0,
		"neutral": 0.0,
	}]


func ml_observation_descriptors() -> Array[Dictionary]:
	return [
		{"name": "installed", "minimum": -1.0, "maximum": 1.0},
		{"name": "realized_thrust_ratio", "minimum": -1.0, "maximum": 1.0},
	]


func ml_encode_observation(runtime_state: Variant, _host_state: Dictionary = {}) -> PackedFloat64Array:
	var state: Dictionary = runtime_state if runtime_state is Dictionary else {}
	var installed: bool = bool(state.get("installed", false))
	var maximum_thrust: float = maxf(float(state.get("maximum_static_thrust_n", 0.0)), 0.000001)
	var realized_thrust: float = maxf(float(state.get("realized_thrust_n", 0.0)), 0.0)
	return PackedFloat64Array([
		1.0 if installed else -1.0,
		clampf(realized_thrust / maximum_thrust, 0.0, 1.5) / 0.75 - 1.0,
	])


func ml_contract_dictionary() -> Dictionary:
	var result: Dictionary = super.ml_contract_dictionary()
	result.merge({
		"max_power_draw": max_power_draw,
		"rotor_radius": rotor_radius,
		"aerodynamic_efficiency": aerodynamic_efficiency,
		"reaction_torque_per_newton": reaction_torque_per_newton,
	}, true)
	return result
