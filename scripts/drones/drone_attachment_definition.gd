@tool
class_name DroneAttachmentDefinition
extends DronePartDefinition

#######################################################
# Defines the serialized drone attachment configuration shared by gameplay, inspection, and
# replication systems.
#######################################################

@export_group("Attachment")
@export var capability_tags: Array[StringName] = []
@export_range(0.0, 10000.0, 0.01, "or_greater") var idle_power_draw := 0.0
@export_range(0.0, 10000.0, 0.01, "or_greater") var active_power_draw := 0.0
@export var body_size := Vector3(0.24, 0.15, 0.3)


func provides_capability(capability: StringName) -> bool:
	return capability in capability_tags


func ml_part_tags() -> Array[StringName]:
	var result: Array[StringName] = [&"drone_part", &"attachment"]
	for tag: StringName in capability_tags:
		if tag not in result:
			result.append(tag)
	return result


func ml_contract_dictionary() -> Dictionary:
	var result: Dictionary = super.ml_contract_dictionary()
	result.merge({
		"capability_tags": capability_tags.duplicate(),
		"idle_power_draw": idle_power_draw,
		"active_power_draw": active_power_draw,
		"body_size": [body_size.x, body_size.y, body_size.z],
	}, true)
	return result
