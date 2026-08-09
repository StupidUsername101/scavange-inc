@tool
class_name FourLimbAttachmentSlotDefinition
extends Resource

#######################################################
# Fixed core attachment port. Future gun or tool nodes can provide a bounded observation feed
# through this slot without changing the four-limb locomotion action contract.
#######################################################

@export var slot_name = "Attachment"
@export var core_offset = Transform3D.IDENTITY
@export var allowed_tags: PackedStringArray = PackedStringArray()


func contract_dictionary() -> Dictionary:
	return {
		"slot_name": slot_name,
		"core_offset": [
			core_offset.basis.x.x, core_offset.basis.x.y, core_offset.basis.x.z,
			core_offset.basis.y.x, core_offset.basis.y.y, core_offset.basis.y.z,
			core_offset.basis.z.x, core_offset.basis.z.y, core_offset.basis.z.z,
			core_offset.origin.x, core_offset.origin.y, core_offset.origin.z,
		],
		"allowed_tags": Array(allowed_tags),
	}


func to_dictionary() -> Dictionary:
	return contract_dictionary()


func apply_dictionary(data: Dictionary) -> void:
	slot_name = str(data.get("slot_name", slot_name))
	var values: Variant = data.get("core_offset", [])
	if values is Array and values.size() >= 12:
		var fallback_values: Array[float] = [
			core_offset.basis.x.x, core_offset.basis.x.y, core_offset.basis.x.z,
			core_offset.basis.y.x, core_offset.basis.y.y, core_offset.basis.y.z,
			core_offset.basis.z.x, core_offset.basis.z.y, core_offset.basis.z.z,
			core_offset.origin.x, core_offset.origin.y, core_offset.origin.z,
		]
		var safe_values: Array[float] = []
		for index in range(12):
			safe_values.append(_finite_float_or(values[index], fallback_values[index]))
		core_offset = Transform3D(
			Basis(
				Vector3(safe_values[0], safe_values[1], safe_values[2]),
				Vector3(safe_values[3], safe_values[4], safe_values[5]),
				Vector3(safe_values[6], safe_values[7], safe_values[8])
			),
			Vector3(safe_values[9], safe_values[10], safe_values[11])
		)
	var tags: Variant = data.get("allowed_tags", [])
	if tags is Array:
		allowed_tags = PackedStringArray(tags as Array)


static func from_dictionary(data: Dictionary) -> FourLimbAttachmentSlotDefinition:
	var result = FourLimbAttachmentSlotDefinition.new()
	result.apply_dictionary(data)
	return result


static func _finite_float_or(value: Variant, fallback: float) -> float:
	if value is float or value is int:
		var numeric_value: float = float(value)
		if is_finite(numeric_value):
			return numeric_value
	return fallback
