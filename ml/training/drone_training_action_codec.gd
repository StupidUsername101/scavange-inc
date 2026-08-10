class_name DroneTrainingActionCodec
extends RefCounted

#######################################################
# Pure conversion helpers for UI/debug telemetry. Policy actions remain in their authored control
# ranges at runtime; action traces use normalized 0..1 values so mixed body interfaces can share
# one visualization without teaching DroneTrainingRoom about every action payload shape.
#######################################################

const LEGACY_QUAD_PROPELLER_COUNT: int = 4


static func policy_unit_commands_from_action(
	body_interface: Dictionary,
	action_value: Variant
) -> PackedFloat64Array:
	if not (action_value is Dictionary):
		return PackedFloat64Array()
	var action: Dictionary = action_value
	var controls_value: Variant = body_interface.get("controls", [])
	var raw_commands: Variant = action.get("body_commands", null)
	var source: PackedFloat64Array = packed_numeric_sequence(raw_commands)
	if controls_value is Array and not source.is_empty():
		var controls: Array = controls_value
		if source.size() == controls.size():
			var result: PackedFloat64Array = PackedFloat64Array()
			result.resize(source.size())
			for index: int in range(source.size()):
				var descriptor_value: Variant = controls[index]
				if not (descriptor_value is Dictionary):
					return PackedFloat64Array()
				var descriptor: Dictionary = descriptor_value
				var minimum: float = float(descriptor.get("minimum", -1.0))
				var maximum: float = float(descriptor.get("maximum", 1.0))
				var value: float = source[index]
				if (
					not is_finite(value)
					or not is_finite(minimum)
					or not is_finite(maximum)
					or maximum <= minimum
				):
					return PackedFloat64Array()
				result[index] = clampf((value - minimum) / (maximum - minimum), 0.0, 1.0)
			return result

	# Compatibility with older quad action dictionaries retained by saved evaluator/debug paths.
	var legacy_value: Variant = action.get("propeller_commands", null)
	if legacy_value is Array:
		var legacy_entries: Array = legacy_value
		if legacy_entries.size() == LEGACY_QUAD_PROPELLER_COUNT:
			var legacy: PackedFloat64Array = PackedFloat64Array()
			legacy.resize(legacy_entries.size())
			for index: int in range(legacy_entries.size()):
				var entry_value: Variant = legacy_entries[index]
				var command_value: Variant = (
					(entry_value as Dictionary).get("command", NAN)
					if entry_value is Dictionary
					else entry_value
				)
				if not (command_value is int or command_value is float):
					return PackedFloat64Array()
				var command: float = float(command_value)
				if not is_finite(command):
					return PackedFloat64Array()
				legacy[index] = clampf(command, 0.0, 1.0)
			return legacy
	var legacy_numeric: PackedFloat64Array = packed_numeric_sequence(legacy_value)
	if legacy_numeric.size() == LEGACY_QUAD_PROPELLER_COUNT:
		for index: int in range(legacy_numeric.size()):
			legacy_numeric[index] = clampf(legacy_numeric[index], 0.0, 1.0)
		return legacy_numeric
	return PackedFloat64Array()


static func packed_numeric_sequence(value: Variant) -> PackedFloat64Array:
	var result: PackedFloat64Array = PackedFloat64Array()
	if value is PackedFloat64Array:
		var source64: PackedFloat64Array = value
		result = source64.duplicate()
	elif value is PackedFloat32Array:
		var source32: PackedFloat32Array = value
		result.resize(source32.size())
		for index: int in range(source32.size()):
			result[index] = source32[index]
	elif value is Array:
		var source_array: Array = value
		result.resize(source_array.size())
		for index: int in range(source_array.size()):
			var element: Variant = source_array[index]
			if not (element is int or element is float):
				return PackedFloat64Array()
			result[index] = float(element)
	else:
		return PackedFloat64Array()
	for element: float in result:
		if not is_finite(element):
			return PackedFloat64Array()
	return result
