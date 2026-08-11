@tool
class_name TurretPartDefinition
extends Resource

@export var display_name = "Turret Part"
@export_range(0.0, 10000.0, 0.05, "or_greater") var mass_kg = 1.0
@export_range(0.0, 1000000.0, 1.0, "or_greater") var maximum_health = 100.0


func to_dictionary() -> Dictionary:
	return {
		"resource_path": resource_path,
		"display_name": display_name,
		"mass_kg": mass_kg,
		"maximum_health": maximum_health,
	}


func hardware_signature_fragment() -> String:
	return JSON.stringify(to_dictionary())


static func vector3_to_json(value: Vector3) -> Array[float]:
	return SafeVariant.vector3_to_array(value)


static func vector3_from_json(value: Variant, fallback: Vector3) -> Vector3:
	return SafeVariant.vector3_strict_or(value, fallback)


static func finite_float_or(value: Variant, fallback: float) -> float:
	return SafeVariant.finite_float_or(value, fallback)


static func finite_int_or(value: Variant, fallback: int) -> int:
	return SafeVariant.finite_int_or(value, fallback)


func ml_part_tags() -> Array[StringName]:
	return [&"turret_part"]


func ml_control_descriptors() -> Array[Dictionary]:
	return []


func ml_observation_descriptors() -> Array[Dictionary]:
	return []


func ml_encode_observation(_runtime_state: Variant, _host_state: Dictionary = {}) -> PackedFloat64Array:
	return PackedFloat64Array()


func ml_contract_dictionary() -> Dictionary:
	return to_dictionary()
