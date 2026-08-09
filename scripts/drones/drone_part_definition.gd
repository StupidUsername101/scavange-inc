@tool
class_name DronePartDefinition
extends Resource

#######################################################
# Defines the serialized drone part configuration shared by gameplay, inspection, and
# replication systems.
#######################################################

enum Quality {
	SCRAP,
	STANDARD,
	INDUSTRIAL,
}

@export_group("Identity")
@export var display_name := "Drone Part"
@export var quality: Quality = Quality.STANDARD
@export var visual_color := Color(0.5, 0.52, 0.56, 1.0)

@export_group("Physical")
@export_range(0.001, 10000.0, 0.001, "or_greater") var mass := 0.1

@export_group("Electrical")
@export_range(0.0, 1000.0, 0.1, "or_greater") var rated_voltage_v := 12.0


func get_mass() -> float:
	return maxf(mass, 0.001)


func ml_part_tags() -> Array[StringName]:
	return [&"drone_part"]


func ml_control_descriptors() -> Array[Dictionary]:
	return []


func ml_observation_descriptors() -> Array[Dictionary]:
	return []


func ml_encode_observation(_runtime_state: Variant, _host_state: Dictionary = {}) -> PackedFloat64Array:
	return PackedFloat64Array()


func ml_contract_dictionary() -> Dictionary:
	return {
		"display_name": display_name,
		"mass": get_mass(),
		"rated_voltage_v": rated_voltage_v,
	}
