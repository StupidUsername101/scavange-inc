@tool
class_name MLRigidCorePartDefinition
extends Resource

#######################################################
# Worker-independent rigid Core physics used by creator presets that do not already have a
# dedicated gameplay Core part. It contains no attachment topology; MLBodyCoreDefinition owns
# the ordered slot list and equipped parts.
#######################################################

@export var display_name: String = "Rigid Core"
@export var body_size: Vector3 = Vector3.ONE
@export_range(0.01, 10000.0, 0.01, "or_greater") var mass_kg: float = 1.0
@export_range(0.01, 1000000.0, 0.01, "or_greater") var maximum_health: float = 100.0
@export_range(0.0, 1.0, 0.01) var friction: float = 0.8
@export_range(0.0, 1.0, 0.01) var bounce: float = 0.0
@export_range(0.0, 100.0, 0.01, "or_greater") var linear_damp: float = 0.0
@export_range(0.0, 100.0, 0.01, "or_greater") var angular_damp: float = 0.0


func sanitize() -> void:
	body_size = Vector3(
		maxf(absf(body_size.x), 0.01),
		maxf(absf(body_size.y), 0.01),
		maxf(absf(body_size.z), 0.01)
	)
	mass_kg = maxf(mass_kg, 0.01) if is_finite(mass_kg) else 1.0
	maximum_health = maxf(maximum_health, 0.01) if is_finite(maximum_health) else 100.0
	friction = clampf(friction, 0.0, 1.0) if is_finite(friction) else 0.8
	bounce = clampf(bounce, 0.0, 1.0) if is_finite(bounce) else 0.0
	linear_damp = maxf(linear_damp, 0.0) if is_finite(linear_damp) else 0.0
	angular_damp = maxf(angular_damp, 0.0) if is_finite(angular_damp) else 0.0


func ml_part_tags() -> Array[StringName]:
	return [&"rigid_core"]


func ml_control_descriptors() -> Array[Dictionary]:
	return []


func ml_observation_descriptors() -> Array[Dictionary]:
	return []


func ml_encode_observation(_runtime_state: Variant, _host_state: Dictionary = {}) -> PackedFloat64Array:
	return PackedFloat64Array()


func ml_contract_dictionary() -> Dictionary:
	return {
		"part_type": "rigid_core",
		"display_name": display_name,
		"body_size": [body_size.x, body_size.y, body_size.z],
		"mass_kg": mass_kg,
		"maximum_health": maximum_health,
		"friction": friction,
		"bounce": bounce,
		"linear_damp": linear_damp,
		"angular_damp": angular_damp,
	}
