class_name SafeVariant
extends RefCounted

#######################################################
# Small, dependency-free decoding helpers for persisted/user-authored Variant data. This is kept
# outside ML code because gameplay resources and model-body resources share the same safe parsing
# rules, and neither should depend on an algorithm utility just to reject NaN/Inf values.
#######################################################


static func is_finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


static func finite_float_or(value: Variant, fallback: float) -> float:
	return float(value) if is_finite_number(value) else fallback


static func finite_int_or(value: Variant, fallback: int) -> int:
	# Compatibility decoder used by older persisted gameplay resources: finite floats are truncated.
	return int(value) if is_finite_number(value) else fallback


static func integral_int_or(value: Variant, fallback: int) -> int:
	# Identity/counter fields must represent an actual integer rather than silently truncating.
	if value is int:
		return int(value)
	if value is float and is_finite(float(value)):
		var numeric_value: float = float(value)
		var rounded_value: float = round(numeric_value)
		if numeric_value == rounded_value:
			return int(rounded_value)
	return fallback


static func bool_or(value: Variant, fallback: bool) -> bool:
	if value is bool:
		return bool(value)
	if value is int:
		return int(value) != 0
	if value is float and is_finite(float(value)):
		return float(value) != 0.0
	return fallback


static func strict_bool_or(value: Variant, fallback: bool) -> bool:
	return bool(value) if value is bool else fallback


static func dictionary_copy(value: Variant, deep: bool = true) -> Dictionary:
	return (value as Dictionary).duplicate(deep) if value is Dictionary else {}


static func dictionary_array_copy(value: Variant, deep: bool = true) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (value is Array):
		return result
	for item: Variant in value:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(deep))
	return result


static func vector3_or(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		var vector_value: Vector3 = value as Vector3
		return vector_value if vector_value.is_finite() else fallback
	if value is Array and (value as Array).size() >= 3:
		var values: Array = value as Array
		var array_result: Vector3 = Vector3(
			finite_float_or(values[0], fallback.x),
			finite_float_or(values[1], fallback.y),
			finite_float_or(values[2], fallback.z)
		)
		return array_result if array_result.is_finite() else fallback
	return fallback


static func vector3_strict_or(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		var vector_value: Vector3 = value as Vector3
		return vector_value if vector_value.is_finite() else fallback
	if value is Array and (value as Array).size() >= 3:
		var array_values: Array = value as Array
		if (
			is_finite_number(array_values[0])
			and is_finite_number(array_values[1])
			and is_finite_number(array_values[2])
		):
			return Vector3(float(array_values[0]), float(array_values[1]), float(array_values[2]))
		return fallback
	if value is Dictionary:
		var dictionary_values: Dictionary = value as Dictionary
		if (
			is_finite_number(dictionary_values.get("x"))
			and is_finite_number(dictionary_values.get("y"))
			and is_finite_number(dictionary_values.get("z"))
		):
			return Vector3(
				float(dictionary_values["x"]),
				float(dictionary_values["y"]),
				float(dictionary_values["z"])
			)
	return fallback


static func vector3_to_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
