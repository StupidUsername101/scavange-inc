class_name RLTrainingVariantCodec
extends RefCounted

#######################################################
# JSON-safe serialization for full optimizer checkpoints. Model checkpoints already contain
# JSON-native arrays/dictionaries; replay/HER continuation additionally contains Vector3,
# Basis, Vector2i and packed arrays. Tags are explicit so integer worker IDs and tensor types
# survive a round-trip instead of being silently converted by JSON dictionary keys.
#######################################################

const TYPE_KEY = "__rl_variant_type"
const VALUE_KEY = "value"
const ENTRIES_KEY = "entries"


static func encode(value: Variant) -> Variant:
	if value == null or value is bool or value is int or value is float or value is String:
		return value
	if value is Vector3:
		var vector3_value: Vector3 = value
		return {TYPE_KEY: "Vector3", VALUE_KEY: [vector3_value.x, vector3_value.y, vector3_value.z]}
	if value is Vector2:
		var vector2_value: Vector2 = value
		return {TYPE_KEY: "Vector2", VALUE_KEY: [vector2_value.x, vector2_value.y]}
	if value is Vector2i:
		var vector2i_value: Vector2i = value
		return {TYPE_KEY: "Vector2i", VALUE_KEY: [vector2i_value.x, vector2i_value.y]}
	if value is Basis:
		var basis: Basis = value
		return {
			TYPE_KEY: "Basis",
			VALUE_KEY: [
				basis.x.x, basis.x.y, basis.x.z,
				basis.y.x, basis.y.y, basis.y.z,
				basis.z.x, basis.z.y, basis.z.z,
			],
		}
	if value is PackedFloat64Array:
		return {TYPE_KEY: "PackedFloat64Array", VALUE_KEY: _numeric_array(value)}
	if value is PackedFloat32Array:
		return {TYPE_KEY: "PackedFloat32Array", VALUE_KEY: _numeric_array(value)}
	if value is PackedInt32Array:
		return {TYPE_KEY: "PackedInt32Array", VALUE_KEY: _numeric_array(value)}
	if value is PackedInt64Array:
		return {TYPE_KEY: "PackedInt64Array", VALUE_KEY: _numeric_array(value)}
	if value is PackedStringArray:
		var strings: Array = []
		for item in value:
			strings.append(str(item))
		return {TYPE_KEY: "PackedStringArray", VALUE_KEY: strings}
	if value is Array:
		var encoded_array: Array = []
		for item in value:
			encoded_array.append(encode(item))
		return encoded_array
	if value is Dictionary:
		var dictionary: Dictionary = value
		var all_string_keys = true
		for key in dictionary:
			if not (key is String):
				all_string_keys = false
				break
		if all_string_keys:
			var encoded_dictionary: Dictionary = {}
			for key in dictionary:
				encoded_dictionary[key] = encode(dictionary[key])
			return encoded_dictionary
		var entries: Array = []
		for key in dictionary:
			entries.append({"key": encode(key), "value": encode(dictionary[key])})
		return {TYPE_KEY: "Dictionary", ENTRIES_KEY: entries}
	return {TYPE_KEY: "Unsupported", VALUE_KEY: str(value)}


static func decode(value: Variant) -> Variant:
	if value is Array:
		var decoded_array: Array = []
		for item in value:
			decoded_array.append(decode(item))
		return decoded_array
	if not (value is Dictionary):
		return value
	var dictionary: Dictionary = value
	var tagged_type = str(dictionary.get(TYPE_KEY, ""))
	if tagged_type.is_empty():
		var decoded_dictionary: Dictionary = {}
		for key in dictionary:
			decoded_dictionary[key] = decode(dictionary[key])
		return decoded_dictionary
	var payload: Variant = dictionary.get(VALUE_KEY, [])
	match tagged_type:
		"Vector3":
			var vector3_values = _decoded_numeric_array(payload, 3)
			return Vector3(vector3_values[0], vector3_values[1], vector3_values[2]) if vector3_values.size() == 3 else Vector3.ZERO
		"Vector2":
			var vector2_values = _decoded_numeric_array(payload, 2)
			return Vector2(vector2_values[0], vector2_values[1]) if vector2_values.size() == 2 else Vector2.ZERO
		"Vector2i":
			var vector2i_values = _decoded_numeric_array(payload, 2)
			return Vector2i(int(vector2i_values[0]), int(vector2i_values[1])) if vector2i_values.size() == 2 else Vector2i.ZERO
		"Basis":
			var basis_values = _decoded_numeric_array(payload, 9)
			if basis_values.size() != 9:
				return Basis.IDENTITY
			return Basis(
				Vector3(basis_values[0], basis_values[1], basis_values[2]),
				Vector3(basis_values[3], basis_values[4], basis_values[5]),
				Vector3(basis_values[6], basis_values[7], basis_values[8])
			)
		"PackedFloat64Array":
			return PackedFloat64Array(_decoded_numeric_values(payload))
		"PackedFloat32Array":
			return PackedFloat32Array(_decoded_numeric_values(payload))
		"PackedInt32Array":
			return PackedInt32Array(_decoded_integer_values(payload))
		"PackedInt64Array":
			return PackedInt64Array(_decoded_integer_values(payload))
		"PackedStringArray":
			return PackedStringArray(_decoded_string_values(payload))
		"Dictionary":
			var decoded_dictionary: Dictionary = {}
			var entries_value: Variant = dictionary.get(ENTRIES_KEY, [])
			if not (entries_value is Array):
				return {}
			var entries: Array = entries_value
			for entry_value in entries:
				if not (entry_value is Dictionary):
					return {}
				var entry: Dictionary = entry_value
				decoded_dictionary[decode(entry.get("key"))] = decode(entry.get("value"))
			return decoded_dictionary
		_:
			return null


static func _numeric_array(value: Variant) -> Array:
	var result: Array = []
	for item in value:
		result.append(item)
	return result


static func _decoded_numeric_array(value: Variant, expected_size: int) -> PackedFloat64Array:
	if not (value is Array) or (value as Array).size() != expected_size:
		return PackedFloat64Array()
	var result = PackedFloat64Array()
	for item in value:
		if not (item is int or item is float) or not is_finite(float(item)):
			return PackedFloat64Array()
		result.append(float(item))
	return result


static func _decoded_numeric_values(value: Variant) -> Array:
	if not (value is Array):
		return []
	var result: Array = []
	for item: Variant in value:
		if not (item is int or item is float) or not is_finite(float(item)):
			return []
		result.append(float(item))
	return result


static func _decoded_integer_values(value: Variant) -> Array:
	if not (value is Array):
		return []
	var result: Array = []
	for item: Variant in value:
		if not (item is int or item is float) or not is_finite(float(item)):
			return []
		var numeric_value: float = float(item)
		var rounded_value: float = round(numeric_value)
		if not is_equal_approx(numeric_value, rounded_value):
			return []
		result.append(int(rounded_value))
	return result


static func _decoded_string_values(value: Variant) -> Array:
	if not (value is Array):
		return []
	var result: Array = []
	for item: Variant in value:
		if not (item is String):
			return []
		result.append(item)
	return result
