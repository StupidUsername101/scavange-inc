class_name MLBodyPartContract
extends RefCounted

const SOURCE_RESOURCE_PATH_META: StringName = &"ml_source_resource_path"

#######################################################
# Duck-typed model interface for serialized body parts. New parts describe their own controls and
# observations on the part definition. The body builder never needs to know whether the part is a
# limb, propeller, gun, tool, or something added later.
#######################################################


static func deep_duplicate_resource(source: Resource) -> Resource:
	if source == null:
		return null
	# Godot's legacy duplicate(true) intentionally leaves Resource values inside Array/Dictionary
	# properties shared. Body definitions use exactly those containers for slots/segments, so accepted
	# model bodies require the 4.6 deep-duplicate API with all subresources included.
	var result: Resource = source.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as Resource
	if result == null:
		return null
	_propagate_source_resource_paths(source, result, {}, 0)
	return result


static func resource_source_path(source: Resource) -> String:
	if source == null:
		return ""
	if not source.resource_path.is_empty():
		return source.resource_path
	for metadata_key: StringName in [
		SOURCE_RESOURCE_PATH_META,
		&"training_source_path",
		&"ml_snapshot_source_path",
	]:
		if source.has_meta(metadata_key):
			var value: String = str(source.get_meta(metadata_key)).strip_edges()
			if not value.is_empty():
				return value
	return ""


static func _propagate_source_resource_paths(
	source: Resource,
	target: Resource,
	seen_pairs: Dictionary,
	depth: int
) -> void:
	if source == null or target == null or depth > 32:
		return
	var pair_key: String = "%d:%d" % [source.get_instance_id(), target.get_instance_id()]
	if seen_pairs.has(pair_key):
		return
	seen_pairs[pair_key] = true
	var source_path: String = resource_source_path(source)
	if not source_path.is_empty():
		target.set_meta(SOURCE_RESOURCE_PATH_META, source_path)
	if source is Script or target is Script:
		return
	for property_value: Variant in source.get_property_list():
		if not (property_value is Dictionary):
			continue
		var property: Dictionary = property_value as Dictionary
		var usage: int = int(property.get("usage", 0))
		if (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var property_name: StringName = StringName(str(property.get("name", "")))
		if str(property_name).is_empty() or property_name == &"script":
			continue
		_propagate_source_paths_variant(
			source.get(property_name),
			target.get(property_name),
			seen_pairs,
			depth + 1
		)


static func _propagate_source_paths_variant(
	source_value: Variant,
	target_value: Variant,
	seen_pairs: Dictionary,
	depth: int
) -> void:
	if depth > 32:
		return
	if source_value is Resource and target_value is Resource:
		_propagate_source_resource_paths(
			source_value as Resource,
			target_value as Resource,
			seen_pairs,
			depth
		)
		return
	if source_value is Array and target_value is Array:
		var source_array: Array = source_value as Array
		var target_array: Array = target_value as Array
		for index: int in range(mini(source_array.size(), target_array.size())):
			_propagate_source_paths_variant(
				source_array[index],
				target_array[index],
				seen_pairs,
				depth + 1
			)
		return
	if source_value is Dictionary and target_value is Dictionary:
		var source_dictionary: Dictionary = source_value as Dictionary
		var target_dictionary: Dictionary = target_value as Dictionary
		for key: Variant in source_dictionary:
			if not target_dictionary.has(key):
				continue
			_propagate_source_paths_variant(
				source_dictionary[key],
				target_dictionary[key],
				seen_pairs,
				depth + 1
			)


static func validation_error(part: Resource) -> String:
	if part == null or not part.has_method("ml_validation_error"):
		return ""
	var value: Variant = part.call("ml_validation_error")
	return str(value).strip_edges()


static func part_tags(part: Resource) -> Array[StringName]:
	if part == null:
		return []
	if part.has_method("ml_part_tags"):
		var value: Variant = part.call("ml_part_tags")
		if value is Array:
			var result: Array[StringName] = []
			for tag_value: Variant in value:
				var tag: StringName = StringName(str(tag_value).strip_edges())
				if not str(tag).is_empty() and tag not in result:
					result.append(tag)
			return result
	return [StringName(part.get_class())]


static func control_descriptors(part: Resource) -> Array[Dictionary]:
	if part == null or not part.has_method("ml_control_descriptors"):
		return []
	return _dictionary_array(part.call("ml_control_descriptors"))


static func observation_descriptors(part: Resource) -> Array[Dictionary]:
	if part == null or not part.has_method("ml_observation_descriptors"):
		return []
	return _dictionary_array(part.call("ml_observation_descriptors"))


static func encode_observation(
	part: Resource,
	runtime_state: Variant,
	host_state: Dictionary = {}
) -> PackedFloat64Array:
	if part == null or not part.has_method("ml_encode_observation"):
		return PackedFloat64Array()
	var value: Variant = part.call("ml_encode_observation", runtime_state, host_state)
	return _packed_finite(value)


static func contract_fragment(part: Resource) -> Dictionary:
	if part == null:
		return {}
	var payload: Dictionary = {
		"class": part.get_class(),
		"script": str(part.get_script().resource_path) if part.get_script() is Script else "",
		"resource_path": resource_source_path(part),
		"tags": _string_tags(part_tags(part)),
		"controls": control_descriptors(part),
		"observations": observation_descriptors(part),
	}
	if part.has_method("ml_contract_dictionary"):
		var value: Variant = part.call("ml_contract_dictionary")
		if value is Dictionary:
			payload["part_contract"] = value
	elif part.has_method("contract_dictionary"):
		var value: Variant = part.call("contract_dictionary")
		if value is Dictionary:
			payload["part_contract"] = value
	elif part.has_method("to_dictionary"):
		var value: Variant = part.call("to_dictionary")
		if value is Dictionary:
			payload["part_contract"] = value
	return payload


static func _string_tags(tags: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for tag: StringName in tags:
		result.append(str(tag))
	return result


static func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (value is Array):
		return result
	for item: Variant in value:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result


static func _packed_finite(value: Variant) -> PackedFloat64Array:
	var result = PackedFloat64Array()
	if value is PackedFloat64Array:
		var source64: PackedFloat64Array = value
		for element: float in source64:
			if not is_finite(element):
				return PackedFloat64Array()
		# PackedFloat64Array already has the exact representation the body manifest consumes. The
		# caller validates ranges before appending, so a second element-for-element copy is pure cost.
		return source64
	if value is PackedFloat32Array:
		var source32: PackedFloat32Array = value
		result.resize(source32.size())
		for index in range(source32.size()):
			if not is_finite(source32[index]):
				return PackedFloat64Array()
			result[index] = source32[index]
		return result
	if not (value is Array):
		return result
	var source: Array = value
	result.resize(source.size())
	for index in range(source.size()):
		var element: Variant = source[index]
		if not (element is int or element is float) or not is_finite(float(element)):
			return PackedFloat64Array()
		result[index] = float(element)
	return result
