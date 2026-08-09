class_name MLBodyActionContract
extends RefCounted

#######################################################
# Worker-independent validation/routing for an action produced against one accepted body manifest.
# Physical worker controllers consume the returned per-Core/per-slot command arrays; they do not
# need to know how the network packed those controls globally.
#######################################################


static func validate(
	action: Dictionary,
	manifest: MLBodyInterfaceManifest
) -> Dictionary:
	if manifest == null or not manifest.finalized:
		return {"valid": false, "error": "The body interface is not finalized."}
	var signature: String = str(action.get("body_interface_signature", ""))
	if signature != manifest.contract_signature:
		return {"valid": false, "error": "The action targets a different body interface manifest."}
	var raw_value: Variant = action.get("body_commands", null)
	var source_size: int = _numeric_sequence_size(raw_value)
	if source_size < 0:
		return {"valid": false, "error": "body_commands must be an Array or packed float array."}
	if source_size != manifest.control_count():
		return {
			"valid": false,
			"error": "Expected %d body commands, received %d." % [
				manifest.control_count(), source_size
			],
		}
	var commands = PackedFloat64Array()
	commands.resize(source_size)
	for index in range(source_size):
		var raw: Variant = _numeric_sequence_value(raw_value, index)
		if not (raw is int or raw is float) or not is_finite(float(raw)):
			return {"valid": false, "error": "Body command %d is not finite numeric data." % index}
		var descriptor: Dictionary = manifest.control_descriptors[index]
		var minimum: float = float(descriptor.get("minimum", -1.0))
		var maximum: float = float(descriptor.get("maximum", 1.0))
		if not is_finite(minimum) or not is_finite(maximum) or maximum <= minimum:
			return {"valid": false, "error": "Body control %d has an invalid authored range." % index}
		commands[index] = clampf(float(raw), minimum, maximum)
	var routed: Dictionary = manifest.route_controls(commands)
	var expected_route_count: int = _controlled_owner_count(manifest)
	if routed.size() != expected_route_count:
		return {"valid": false, "error": "The body command router rejected the finalized manifest."}
	return {"valid": true, "commands": commands, "routed": routed}


static func _controlled_owner_count(manifest: MLBodyInterfaceManifest) -> int:
	var result: int = 0
	if int(manifest.core_record.get("control_count", 0)) > 0:
		result += 1
	for record: Dictionary in manifest.slot_records:
		if int(record.get("control_count", 0)) > 0:
			result += 1
	return result


static func _numeric_sequence_size(value: Variant) -> int:
	if value is Array:
		var source_array: Array = value
		return source_array.size()
	if value is PackedFloat32Array:
		var source32: PackedFloat32Array = value
		return source32.size()
	if value is PackedFloat64Array:
		var source64: PackedFloat64Array = value
		return source64.size()
	return -1


static func _numeric_sequence_value(value: Variant, index: int) -> Variant:
	if value is Array:
		var source_array: Array = value
		return source_array[index]
	if value is PackedFloat32Array:
		var source32: PackedFloat32Array = value
		return source32[index]
	if value is PackedFloat64Array:
		var source64: PackedFloat64Array = value
		return source64[index]
	return null
