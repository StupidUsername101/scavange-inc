class_name MLBodyResourceSnapshot
extends RefCounted

#######################################################
# Generic JSON-safe Resource snapshot used by accepted/body-creator hardware records. Model parts
# are ordinary Resources, so persistence must follow their exported/storage properties instead of
# maintaining one serializer per worker/attachment type. This is intentionally independent of the
# neural manifest: a future gun/tool/limb can add exported data without changing the body builder.
#######################################################

const SCHEMA_VERSION: int = 1
const TYPE_KEY: String = "__ml_variant_type"
const MAXIMUM_RECURSION_DEPTH: int = 32
const UNSUPPORTED_KEY: String = "__ml_snapshot_unsupported"
const SUPPORTED_TYPE_TAGS: Array[String] = [
	"int",
	"string_name",
	"node_path",
	"vector2",
	"vector2i",
	"vector3",
	"vector3i",
	"vector4",
	"vector4i",
	"color",
	"quaternion",
	"basis",
	"transform3d",
	"array",
	"dictionary",
	"packed_byte_array",
	"packed_int32_array",
	"packed_int64_array",
	"packed_float32_array",
	"packed_float64_array",
	"packed_string_array",
	"packed_vector2_array",
	"packed_vector3_array",
	"packed_vector4_array",
	"packed_color_array",
	"resource",
]
const SKIPPED_RESOURCE_PROPERTIES: Array[StringName] = [
	&"script",
	&"resource_name",
	&"resource_local_to_scene",
	&"resource_path",
]


static func encode_resource(source: Resource) -> Dictionary:
	if source == null:
		return {}
	var encoded: Dictionary = _encode_resource(source, {}, 0)
	if _contains_unsupported(encoded):
		return {}
	return encoded


static func decode_resource(snapshot: Dictionary) -> Resource:
	if (
		snapshot.is_empty()
		or _contains_unsupported(snapshot)
		or _contains_unknown_type_tag(snapshot)
	):
		return null
	return _decode_resource(snapshot, 0)


static func _encode_resource(
	source: Resource,
	seen: Dictionary,
	depth: int
) -> Dictionary:
	if source == null:
		return {}
	if depth > MAXIMUM_RECURSION_DEPTH:
		return _unsupported_record("resource_recursion_depth")
	var source_id: int = source.get_instance_id()
	if seen.has(source_id):
		# Body part graphs are expected to be trees. Fail closed on cycles instead of recursing forever
		# or serializing a reference whose lifetime would be ambiguous after checkpoint restore.
		return _unsupported_record("resource_cycle")
	seen[source_id] = true
	var script_value: Variant = source.get_script()
	var script_path: String = (
		str((script_value as Script).resource_path)
		if script_value is Script
		else ""
	)
	var resource_path: String = source.resource_path
	if resource_path.is_empty():
		resource_path = MLBodyPartContract.resource_source_path(source)
	var properties: Dictionary = {}
	if not (source is Script):
		for property_value: Variant in source.get_property_list():
			if not (property_value is Dictionary):
				continue
			var property: Dictionary = property_value
			var property_name: StringName = StringName(str(property.get("name", "")))
			var usage: int = int(property.get("usage", 0))
			if (
				str(property_name).is_empty()
				or property_name in SKIPPED_RESOURCE_PROPERTIES
				or (usage & PROPERTY_USAGE_STORAGE) == 0
			):
				continue
			properties[str(property_name)] = _encode_variant(
				source.get(property_name),
				seen,
				depth + 1
			)
	seen.erase(source_id)
	return {
		"schema_version": SCHEMA_VERSION,
		"resource_path": resource_path,
		"script_path": script_path,
		"properties": properties,
	}


static func _decode_resource(snapshot: Dictionary, depth: int) -> Resource:
	if snapshot.is_empty() or depth > MAXIMUM_RECURSION_DEPTH:
		return null
	if int(snapshot.get("schema_version", -1)) != SCHEMA_VERSION:
		return null
	var resource_path: String = str(snapshot.get("resource_path", ""))
	var script_path: String = str(snapshot.get("script_path", ""))
	var accepted_resource_path: String = ""
	var result: Resource = null
	if not resource_path.is_empty() and ResourceLoader.exists(resource_path):
		var source: Resource = load(resource_path) as Resource
		if _resource_matches_script(source, script_path):
			result = MLBodyPartContract.deep_duplicate_resource(source)
			if result != null:
				accepted_resource_path = resource_path
	if result == null and not script_path.is_empty() and ResourceLoader.exists(script_path):
		var script_resource: Script = load(script_path) as Script
		if script_resource != null:
			var instance: Variant = script_resource.new()
			if instance is Resource:
				result = instance as Resource
	if result == null:
		return null
	var properties_value: Variant = snapshot.get("properties", {})
	if not (properties_value is Dictionary):
		return null
	var properties: Dictionary = properties_value
	var known_properties: Dictionary = {}
	for property_value: Variant in result.get_property_list():
		if property_value is Dictionary:
			known_properties[str((property_value as Dictionary).get("name", ""))] = true
	for property_name_value: Variant in properties.keys():
		var property_name: String = str(property_name_value)
		if not known_properties.has(property_name):
			return null
		var template: Variant = result.get(property_name)
		var decoded: Variant = _decode_variant(properties[property_name_value], template, depth + 1)
		result.set(property_name, decoded)
	if not accepted_resource_path.is_empty():
		result.set_meta("ml_snapshot_source_path", accepted_resource_path)
	return result


static func _resource_matches_script(source: Resource, script_path: String) -> bool:
	if source == null:
		return false
	if script_path.is_empty():
		return true
	var source_script_value: Variant = source.get_script()
	if not (source_script_value is Script):
		return false
	var source_script: Script = source_script_value as Script
	return str(source_script.resource_path) == script_path


static func _encode_variant(value: Variant, seen: Dictionary, depth: int) -> Variant:
	if depth > MAXIMUM_RECURSION_DEPTH:
		return _unsupported_record("variant_recursion_depth")
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_INT:
			# JSON parses unannotated numbers without preserving integer key/value intent. Keep integers
			# tagged so dictionaries and future enum/index maps round-trip without type drift.
			return {TYPE_KEY: "int", "value": value}
		TYPE_STRING_NAME:
			return {TYPE_KEY: "string_name", "value": str(value)}
		TYPE_NODE_PATH:
			return {TYPE_KEY: "node_path", "value": str(value)}
		TYPE_VECTOR2:
			return {TYPE_KEY: "vector2", "value": [value.x, value.y]}
		TYPE_VECTOR2I:
			return {TYPE_KEY: "vector2i", "value": [value.x, value.y]}
		TYPE_VECTOR3:
			return {TYPE_KEY: "vector3", "value": [value.x, value.y, value.z]}
		TYPE_VECTOR3I:
			return {TYPE_KEY: "vector3i", "value": [value.x, value.y, value.z]}
		TYPE_VECTOR4:
			return {TYPE_KEY: "vector4", "value": [value.x, value.y, value.z, value.w]}
		TYPE_VECTOR4I:
			return {TYPE_KEY: "vector4i", "value": [value.x, value.y, value.z, value.w]}
		TYPE_COLOR:
			return {TYPE_KEY: "color", "value": [value.r, value.g, value.b, value.a]}
		TYPE_QUATERNION:
			return {TYPE_KEY: "quaternion", "value": [value.x, value.y, value.z, value.w]}
		TYPE_BASIS:
			return {
				TYPE_KEY: "basis",
				"value": [
					[value.x.x, value.x.y, value.x.z],
					[value.y.x, value.y.y, value.y.z],
					[value.z.x, value.z.y, value.z.z],
				],
			}
		TYPE_TRANSFORM3D:
			return {
				TYPE_KEY: "transform3d",
				"basis": _encode_variant(value.basis, seen, depth + 1),
				"origin": _encode_variant(value.origin, seen, depth + 1),
			}
		TYPE_ARRAY:
			var items: Array = []
			for item: Variant in value:
				items.append(_encode_variant(item, seen, depth + 1))
			return {TYPE_KEY: "array", "items": items}
		TYPE_DICTIONARY:
			var entries: Array[Dictionary] = []
			for key: Variant in value.keys():
				entries.append({
					"key": _encode_variant(key, seen, depth + 1),
					"value": _encode_variant(value[key], seen, depth + 1),
				})
			return {TYPE_KEY: "dictionary", "entries": entries}
		TYPE_PACKED_BYTE_ARRAY:
			return {TYPE_KEY: "packed_byte_array", "value": _packed_scalar_values(value)}
		TYPE_PACKED_INT32_ARRAY:
			return {TYPE_KEY: "packed_int32_array", "value": _packed_scalar_values(value)}
		TYPE_PACKED_INT64_ARRAY:
			return {TYPE_KEY: "packed_int64_array", "value": _packed_scalar_values(value)}
		TYPE_PACKED_FLOAT32_ARRAY:
			return {TYPE_KEY: "packed_float32_array", "value": _packed_scalar_values(value)}
		TYPE_PACKED_FLOAT64_ARRAY:
			return {TYPE_KEY: "packed_float64_array", "value": _packed_scalar_values(value)}
		TYPE_PACKED_STRING_ARRAY:
			return {TYPE_KEY: "packed_string_array", "value": _packed_scalar_values(value)}
		TYPE_PACKED_VECTOR2_ARRAY:
			var vector2_items: Array = []
			for item: Vector2 in value:
				vector2_items.append(_encode_variant(item, seen, depth + 1))
			return {TYPE_KEY: "packed_vector2_array", "value": vector2_items}
		TYPE_PACKED_VECTOR3_ARRAY:
			var vector3_items: Array = []
			for item: Vector3 in value:
				vector3_items.append(_encode_variant(item, seen, depth + 1))
			return {TYPE_KEY: "packed_vector3_array", "value": vector3_items}
		TYPE_PACKED_VECTOR4_ARRAY:
			var vector4_items: Array = []
			for item: Vector4 in value:
				vector4_items.append(_encode_variant(item, seen, depth + 1))
			return {TYPE_KEY: "packed_vector4_array", "value": vector4_items}
		TYPE_PACKED_COLOR_ARRAY:
			var color_items: Array = []
			for item: Color in value:
				color_items.append(_encode_variant(item, seen, depth + 1))
			return {TYPE_KEY: "packed_color_array", "value": color_items}
		TYPE_OBJECT:
			if value is Resource:
				return {
					TYPE_KEY: "resource",
					"value": _encode_resource(value as Resource, seen, depth + 1),
				}
	return _unsupported_record("variant_type_%d" % typeof(value))


static func _decode_variant(encoded: Variant, template: Variant, depth: int) -> Variant:
	if depth > MAXIMUM_RECURSION_DEPTH:
		return null
	if not (encoded is Dictionary) or not (encoded as Dictionary).has(TYPE_KEY):
		return _coerce_scalar(encoded, template)
	var record: Dictionary = encoded as Dictionary
	var kind: String = str(record.get(TYPE_KEY, ""))
	var value: Variant = record.get("value", null)
	match kind:
		"int":
			return int(value)
		"string_name":
			return StringName(str(value))
		"node_path":
			return NodePath(str(value))
		"vector2":
			return Vector2(float(value[0]), float(value[1])) if value is Array and value.size() >= 2 else Vector2.ZERO
		"vector2i":
			return Vector2i(int(value[0]), int(value[1])) if value is Array and value.size() >= 2 else Vector2i.ZERO
		"vector3":
			return Vector3(float(value[0]), float(value[1]), float(value[2])) if value is Array and value.size() >= 3 else Vector3.ZERO
		"vector3i":
			return Vector3i(int(value[0]), int(value[1]), int(value[2])) if value is Array and value.size() >= 3 else Vector3i.ZERO
		"vector4":
			return Vector4(float(value[0]), float(value[1]), float(value[2]), float(value[3])) if value is Array and value.size() >= 4 else Vector4.ZERO
		"vector4i":
			return Vector4i(int(value[0]), int(value[1]), int(value[2]), int(value[3])) if value is Array and value.size() >= 4 else Vector4i.ZERO
		"color":
			return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3])) if value is Array and value.size() >= 4 else Color.BLACK
		"quaternion":
			return Quaternion(float(value[0]), float(value[1]), float(value[2]), float(value[3])) if value is Array and value.size() >= 4 else Quaternion.IDENTITY
		"basis":
			return _decode_basis(value)
		"transform3d":
			var basis: Basis = _decode_variant(record.get("basis", {}), Basis.IDENTITY, depth + 1)
			var origin: Vector3 = _decode_variant(record.get("origin", {}), Vector3.ZERO, depth + 1)
			return Transform3D(basis, origin)
		"array":
			return _decode_array(record.get("items", []), template, depth + 1)
		"dictionary":
			return _decode_dictionary(record.get("entries", []), template, depth + 1)
		"packed_byte_array":
			return PackedByteArray(value if value is Array else [])
		"packed_int32_array":
			return PackedInt32Array(value if value is Array else [])
		"packed_int64_array":
			return PackedInt64Array(value if value is Array else [])
		"packed_float32_array":
			return PackedFloat32Array(value if value is Array else [])
		"packed_float64_array":
			return PackedFloat64Array(value if value is Array else [])
		"packed_string_array":
			return PackedStringArray(value if value is Array else [])
		"packed_vector2_array":
			return _decode_packed_vector2_array(value, depth + 1)
		"packed_vector3_array":
			return _decode_packed_vector3_array(value, depth + 1)
		"packed_vector4_array":
			return _decode_packed_vector4_array(value, depth + 1)
		"packed_color_array":
			return _decode_packed_color_array(value, depth + 1)
		"resource":
			return _decode_resource(value as Dictionary, depth + 1) if value is Dictionary else null
	return null


static func _decode_array(encoded_items: Variant, template: Variant, depth: int) -> Array:
	var result: Array = template.duplicate() if template is Array else []
	result.clear()
	if not (encoded_items is Array):
		return result
	var template_array: Array = template if template is Array else []
	for index in range((encoded_items as Array).size()):
		var item_template: Variant = template_array[index] if index < template_array.size() else null
		result.append(_decode_variant((encoded_items as Array)[index], item_template, depth + 1))
	return result


static func _decode_dictionary(encoded_entries: Variant, template: Variant, depth: int) -> Dictionary:
	var result: Dictionary = template.duplicate() if template is Dictionary else {}
	result.clear()
	if not (encoded_entries is Array):
		return result
	for entry_value: Variant in encoded_entries:
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		var key: Variant = _decode_variant(entry.get("key", null), null, depth + 1)
		var item_template: Variant = template.get(key, null) if template is Dictionary else null
		result[key] = _decode_variant(entry.get("value", null), item_template, depth + 1)
	return result


static func _decode_basis(value: Variant) -> Basis:
	if not (value is Array) or value.size() < 3:
		return Basis.IDENTITY
	var rows: Array = value
	for row: Variant in rows:
		if not (row is Array) or row.size() < 3:
			return Basis.IDENTITY
	return Basis(
		Vector3(float(rows[0][0]), float(rows[0][1]), float(rows[0][2])),
		Vector3(float(rows[1][0]), float(rows[1][1]), float(rows[1][2])),
		Vector3(float(rows[2][0]), float(rows[2][1]), float(rows[2][2]))
	)


static func _packed_scalar_values(value: Variant) -> Array:
	# Avoid relying on Packed*Array -> Array constructor coercion. Explicit iteration is stable for
	# every packed scalar/string array and remains JSON-safe.
	var result: Array = []
	for item: Variant in value:
		result.append(item)
	return result


static func _decode_packed_vector2_array(value: Variant, depth: int) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	if value is Array:
		for item: Variant in value:
			var decoded: Variant = _decode_variant(item, Vector2.ZERO, depth + 1)
			if decoded is Vector2:
				result.append(decoded)
	return result


static func _decode_packed_vector3_array(value: Variant, depth: int) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	if value is Array:
		for item: Variant in value:
			var decoded: Variant = _decode_variant(item, Vector3.ZERO, depth + 1)
			if decoded is Vector3:
				result.append(decoded)
	return result


static func _decode_packed_vector4_array(value: Variant, depth: int) -> PackedVector4Array:
	var result: PackedVector4Array = PackedVector4Array()
	if value is Array:
		for item: Variant in value:
			var decoded: Variant = _decode_variant(item, Vector4.ZERO, depth + 1)
			if decoded is Vector4:
				result.append(decoded)
	return result


static func _decode_packed_color_array(value: Variant, depth: int) -> PackedColorArray:
	var result: PackedColorArray = PackedColorArray()
	if value is Array:
		for item: Variant in value:
			var decoded: Variant = _decode_variant(item, Color.WHITE, depth + 1)
			if decoded is Color:
				result.append(decoded)
	return result


static func _unsupported_record(reason: String) -> Dictionary:
	return {UNSUPPORTED_KEY: true, "reason": reason}


static func _contains_unknown_type_tag(value: Variant) -> bool:
	if value is Dictionary:
		var dictionary: Dictionary = value
		if dictionary.has(TYPE_KEY):
			var kind: String = str(dictionary.get(TYPE_KEY, ""))
			if kind not in SUPPORTED_TYPE_TAGS:
				return true
		for nested: Variant in dictionary.values():
			if _contains_unknown_type_tag(nested):
				return true
		return false
	if value is Array:
		for nested: Variant in value:
			if _contains_unknown_type_tag(nested):
				return true
	return false


static func _contains_unsupported(value: Variant) -> bool:
	if value is Dictionary:
		var dictionary: Dictionary = value
		if bool(dictionary.get(UNSUPPORTED_KEY, false)):
			return true
		for nested: Variant in dictionary.values():
			if _contains_unsupported(nested):
				return true
		return false
	if value is Array:
		for nested: Variant in value:
			if _contains_unsupported(nested):
				return true
	return false


static func _coerce_scalar(value: Variant, template: Variant) -> Variant:
	match typeof(template):
		TYPE_BOOL:
			return bool(value)
		TYPE_INT:
			return int(value)
		TYPE_FLOAT:
			return float(value)
		TYPE_STRING:
			return str(value)
		TYPE_STRING_NAME:
			return StringName(str(value))
	return value
