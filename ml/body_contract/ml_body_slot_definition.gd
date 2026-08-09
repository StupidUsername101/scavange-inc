@tool
class_name MLBodySlotDefinition
extends Resource

#######################################################
# Generic model-forge slot contract. Gameplay bodies may keep their existing serialized slot
# arrays/counts; adapters expose those slots through this resource so the model builder has one
# ordered, typed representation across drones, articulated bodies, turrets, and future bodies.
#######################################################

@export var slot_id: StringName = &"slot"
@export var display_name: String = "Attachment slot"
@export var slot_type: StringName = &"generic"
@export var accepted_part_tags: Array[StringName] = []
@export var mount_transform: Transform3D = Transform3D.IDENTITY


func accepts(part: Resource) -> bool:
	if part == null:
		return true
	if accepted_part_tags.is_empty():
		return true
	var tags: Array[StringName] = MLBodyPartContract.part_tags(part)
	for required_tag: StringName in accepted_part_tags:
		if required_tag in tags:
			return true
	return false


func contract_dictionary() -> Dictionary:
	return {
		"slot_id": str(slot_id),
		"display_name": display_name,
		"slot_type": str(slot_type),
		"accepted_part_tags": _accepted_tags_as_strings(),
		"mount_origin": [
			mount_transform.origin.x,
			mount_transform.origin.y,
			mount_transform.origin.z,
		],
		"mount_basis": [
			[mount_transform.basis.x.x, mount_transform.basis.x.y, mount_transform.basis.x.z],
			[mount_transform.basis.y.x, mount_transform.basis.y.y, mount_transform.basis.y.z],
			[mount_transform.basis.z.x, mount_transform.basis.z.y, mount_transform.basis.z.z],
		],
	}


func _accepted_tags_as_strings() -> Array[String]:
	var result: Array[String] = []
	for tag: StringName in accepted_part_tags:
		result.append(str(tag))
	return result
