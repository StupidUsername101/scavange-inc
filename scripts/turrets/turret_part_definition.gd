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
	return [value.x, value.y, value.z]


static func vector3_from_json(value: Variant, fallback: Vector3) -> Vector3:
	var result = fallback
	if value is Vector3:
		result = value
	elif value is Array and value.size() >= 3:
		if _finite_number(value[0]) and _finite_number(value[1]) and _finite_number(value[2]):
			result = Vector3(float(value[0]), float(value[1]), float(value[2]))
	elif value is Dictionary:
		if _finite_number(value.get("x")) and _finite_number(value.get("y")) and _finite_number(value.get("z")):
			result = Vector3(float(value["x"]), float(value["y"]), float(value["z"]))
	return result if result.is_finite() else fallback


static func finite_float_or(value: Variant, fallback: float) -> float:
	return float(value) if _finite_number(value) else fallback


static func finite_int_or(value: Variant, fallback: int) -> int:
	return int(value) if _finite_number(value) else fallback


static func _finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


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
